defmodule Ecto.Druid.TestTasks do
  @moduledoc false

  # Shuts down the ingestion tasks still active for a test's data sources.
  #
  # A test that fails or times out while it waits on a task stops waiting, but
  # the task keeps running, or stays pending. SQL-based ingestion needs a slot
  # for its controller and another for each worker, so controllers left behind
  # can take every slot and leave the next run's workers waiting for one.
  # Call this from on_exit, before anything that drops the data source.

  @druid [host: "localhost", port: 9888]
  @states ~w(running pending waiting)

  def shutdown_all(data_sources, timeout \\ 60_000) do
    data_sources = List.wrap(data_sources)

    # Druid 38 answers the shutdownAllTasks endpoint with a 404 even while a
    # data source has active tasks, so each task is shut down by its id.
    # Shutting down a task that has just finished returns an error, which is
    # fine here.
    for task_id <- active(data_sources) do
      Druid.Client.Task.shutdown(task_id) |> Druid.Client.request(@druid)
    end

    # Shutting down is asynchronous. Wait for the slots to be free, so the
    # next test doesn't start with them taken.
    check = fn ->
      case active(data_sources) do
        [] -> {:done, :ok}
        task_ids -> {:wait, task_ids}
      end
    end

    case Druid.Poll.poll(Druid.Poll.deadline(timeout), 500, check) do
      {:ok, :ok} -> :ok
      {:timeout, task_ids} -> raise "tasks still active after #{timeout}ms: #{inspect(task_ids)}"
    end
  end

  defp active(data_sources) do
    for data_source <- data_sources,
        state <- @states,
        %{"id" => id} <-
          Druid.Client.Task.all(state: state, datasource: data_source)
          |> Druid.Client.request!(@druid),
        uniq: true,
        do: id
  end
end
