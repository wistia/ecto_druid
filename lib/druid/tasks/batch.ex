defmodule Druid.Tasks.Batch do
  @moduledoc false
  # Submits a list of Druid.Tasks.Run, at most `:concurrency` at a time, and
  # polls them with the bulk task status API until they finish. Used by
  # Druid.Tasks.backfill/5 and Druid.Tasks.await_all/3.

  alias Druid.Tasks.{Error, Run}

  @finished ["SUCCESS", "FAILED"]

  def run(runs, request_opts, opts) do
    concurrency = Keyword.get(opts, :concurrency, :infinity)
    await? = Keyword.get(opts, :await, true)
    poll_interval = Keyword.fetch!(opts, :poll_interval)
    deadline = deadline(Keyword.get(opts, :timeout, :infinity))

    state = %{
      queue: [],
      active: [],
      done: [],
      concurrency: concurrency,
      await?: await?,
      poll_interval: poll_interval,
      deadline: deadline,
      request_opts: request_opts,
      on_submit: Keyword.get(opts, :on_submit, fn _run -> :ok end),
      on_progress: Keyword.get(opts, :on_progress, fn _progress -> :ok end),
      total: length(runs),
      last_progress: nil
    }

    {queue, active} =
      runs
      |> Enum.with_index()
      |> Enum.split_with(fn {run, _index} -> is_nil(run.task_id) end)

    %{state | queue: queue, active: active}
    |> loop()
    |> Enum.sort_by(fn {_run, index} -> index end)
    |> Enum.map(fn {run, _index} -> run end)
  end

  @doc "Fetches the current status of each run in one request."
  def refresh(runs, request_opts) do
    ids = for %Run{task_id: id} when is_binary(id) <- runs, do: id

    case fetch_statuses(ids, request_opts) do
      {:ok, statuses} ->
        Enum.map(runs, fn
          %Run{task_id: nil} = run -> run
          run -> apply_status(run, Map.get(statuses, run.task_id))
        end)

      {:error, error} ->
        Enum.map(runs, &%{&1 | error: &1.error || error})
    end
  end

  def progress(runs, total \\ nil) do
    counts =
      Enum.reduce(runs, %{succeeded: 0, failed: 0, running: 0, pending: 0}, fn run, acc ->
        key =
          cond do
            run.error -> :failed
            run.status && run.status["status"] == "SUCCESS" -> :succeeded
            run.task_id -> :running
            true -> :pending
          end

        Map.update!(acc, key, &(&1 + 1))
      end)

    Map.put(counts, :total, total || length(runs))
  end

  defp loop(state) do
    state = submit_ready(state)

    cond do
      state.active == [] and state.queue == [] ->
        report(state)
        state.done

      state.queue == [] and not state.await? ->
        report(state)
        state.done ++ state.active

      true ->
        state = poll(state)

        cond do
          state.active == [] and state.queue == [] ->
            report(state)
            state.done

          remaining(state.deadline) == 0 ->
            timed_out(state)

          true ->
            Process.sleep(min(state.poll_interval, remaining(state.deadline)))
            loop(state)
        end
    end
  end

  defp submit_ready(%{queue: [{run, index} | rest]} = state) do
    if slots?(state) do
      run = submit(run, state.request_opts)
      if run.task_id, do: state.on_submit.(run)

      state =
        if run.error,
          do: %{state | queue: rest, done: [{run, index} | state.done]},
          else: %{state | queue: rest, active: state.active ++ [{run, index}]}

      submit_ready(state)
    else
      state
    end
  end

  defp submit_ready(state), do: state

  defp slots?(%{concurrency: :infinity}), do: true
  defp slots?(state), do: length(state.active) < state.concurrency

  defp submit(run, request_opts) do
    case Druid.Client.Task.submit(run.spec) |> Druid.Client.request(request_opts) do
      {:ok, %{"task" => task_id}} ->
        %{run | task_id: task_id}

      {:ok, body} ->
        %{run | error: %Error{message: "unexpected response from Druid: #{inspect(body)}"}}

      {:error, error} ->
        %{run | error: error}
    end
  end

  defp poll(state) do
    {runs, indexes} = Enum.unzip(state.active)

    case fetch_statuses(Enum.map(runs, & &1.task_id), state.request_opts) do
      {:ok, statuses} ->
        {finished, active} =
          runs
          |> Enum.map(&apply_status(&1, Map.get(statuses, &1.task_id)))
          |> Enum.zip(indexes)
          |> Enum.split_with(fn {run, _index} -> finished?(run) end)

        report(%{state | active: active, done: finished ++ state.done})

      {:error, error} ->
        # A failed status request fails the runs it was for, rather than
        # retrying forever. Req already retries transient errors.
        failed = Enum.map(state.active, fn {run, index} -> {%{run | error: error}, index} end)
        report(%{state | active: [], done: failed ++ state.done})
    end
  end

  defp fetch_statuses([], _request_opts), do: {:ok, %{}}

  defp fetch_statuses(ids, request_opts),
    do: Druid.Client.Task.statuses(ids) |> Druid.Client.request(request_opts)

  defp apply_status(run, nil) do
    %{run | error: %Error{message: "Druid has no task #{run.task_id}", task_id: run.task_id}}
  end

  defp apply_status(run, %{"status" => "FAILED"} = status) do
    message =
      case status["errorMsg"] do
        nil -> "task #{run.task_id} failed"
        error -> "task #{run.task_id} failed: #{error}"
      end

    %{
      run
      | status: status,
        error: %Error{message: message, reason: :failed, task_id: run.task_id, status: status}
    }
  end

  defp apply_status(run, status), do: %{run | status: status}

  defp finished?(run), do: run.error != nil or run.status["status"] in @finished

  defp timed_out(state) do
    active =
      Enum.map(state.active, fn {run, index} ->
        error = %Error{
          message: "timed out waiting for task #{run.task_id}",
          reason: :timeout,
          task_id: run.task_id,
          status: run.status
        }

        {%{run | error: error}, index}
      end)

    queued =
      Enum.map(state.queue, fn {run, index} ->
        error = %Error{message: "timed out before the task was submitted", reason: :timeout}
        {%{run | error: error}, index}
      end)

    state = %{state | active: [], queue: [], done: active ++ queued ++ state.done}
    report(state)
    state.done
  end

  defp report(state) do
    runs = Enum.map(state.done ++ state.active ++ state.queue, &elem(&1, 0))
    progress = progress(runs, state.total)

    if progress != state.last_progress, do: state.on_progress.(progress)
    %{state | last_progress: progress}
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
