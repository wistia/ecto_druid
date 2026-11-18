defmodule Ecto.Adapters.Druid.Statement do
  @moduledoc false

  # Runs queries through Druid's query from deep storage API: submit the
  # statement, poll its status until it finishes, then read its result pages.

  alias Druid.Client.SQL.Statement
  alias Ecto.Adapters.Druid.{StatementError, Telemetry}

  @default_timeout :timer.minutes(5)
  @default_poll_interval 1_000

  @doc """
  Returns the deep storage options for a query, or `nil` when it should go to
  the Broker. `:deep_storage` is `true`, `false`, or a keyword list of
  options, and a per-query value replaces the repo config value.
  """
  @spec options(Keyword.t()) :: Keyword.t() | nil
  def options(opts) do
    case Keyword.get(opts, :deep_storage, false) do
      value when value in [nil, false] ->
        nil

      true ->
        []

      list when is_list(list) ->
        list

      other ->
        raise ArgumentError,
              "expected :deep_storage to be a boolean or keyword list, got: #{inspect(other)}"
    end
  end

  @doc """
  Runs a statement and returns all of its rows.
  """
  @spec all(String.t(), list(), Keyword.t(), Keyword.t()) :: [list()]
  def all(sql, params, deep_storage, request_opts) do
    %{"queryId" => query_id} = await(sql, params, deep_storage, request_opts)

    Statement.results(query_id, result_format: "array")
    |> Telemetry.request!(request_opts)
    |> rows()
  end

  @doc """
  Returns a stream that runs a statement when it is first enumerated, then
  fetches one result page at a time as `{num_rows, rows}`.

  `around_await` is called with a function that runs the statement and
  returns its status, and must return that status. The adapter wraps it in
  the query's telemetry.
  """
  @spec stream(String.t(), list(), Keyword.t(), Keyword.t(), ((-> map()) -> map())) ::
          Enumerable.t()
  def stream(sql, params, deep_storage, request_opts, around_await \\ & &1.()) do
    Stream.resource(
      fn ->
        %{"queryId" => query_id} =
          status = around_await.(fn -> await(sql, params, deep_storage, request_opts) end)

        {query_id, page_ids(status)}
      end,
      fn
        {_query_id, []} = acc ->
          {:halt, acc}

        {query_id, [page | pages]} ->
          rows =
            Statement.results(query_id, page: page, result_format: "array")
            |> Telemetry.request!(request_opts)
            |> rows()

          {[{length(rows), rows}], {query_id, pages}}
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Submits a statement and waits for it to succeed, returning its final
  status. Raises `Ecto.Adapters.Druid.StatementError` if it fails, is
  canceled, or runs past `:timeout`, canceling it in the last case.
  """
  @spec await(String.t(), list(), Keyword.t(), Keyword.t()) :: map()
  def await(sql, params, deep_storage, request_opts) do
    timeout = Keyword.get(deep_storage, :timeout, @default_timeout)
    poll_interval = Keyword.get(deep_storage, :poll_interval, @default_poll_interval)
    deadline = deadline(timeout)

    Statement.submit(sql, params, context: Keyword.get(request_opts, :context, %{}))
    |> Telemetry.request!(request_opts)
    |> poll(deadline, poll_interval, timeout, request_opts)
  end

  defp poll(%{"state" => "SUCCESS"} = status, _deadline, _interval, _timeout, _opts), do: status

  defp poll(%{"state" => state} = status, _deadline, _interval, _timeout, _opts)
       when state in ["FAILED", "CANCELED"] do
    raise StatementError.exception(status)
  end

  defp poll(%{"queryId" => query_id} = status, deadline, interval, timeout, opts) do
    case remaining(deadline) do
      0 ->
        # The statement keeps running in Druid unless it is canceled
        _ = Statement.cancel(query_id) |> Druid.Client.request(opts)

        raise StatementError,
          message:
            "Statement #{query_id} did not finish within #{timeout}ms (last state " <>
              "#{status["state"]}). It was canceled.",
          query_id: query_id,
          state: status["state"]

      remaining ->
        Process.sleep(min(interval, remaining))

        Statement.status(query_id)
        |> Telemetry.request!(opts)
        |> poll(deadline, interval, timeout, opts)
    end
  end

  @doc """
  Returns how many rows a finished statement's results hold.
  """
  @spec num_rows(map()) :: non_neg_integer()
  def num_rows(status) do
    case get_in(status, ["result", "numTotalRows"]) do
      rows when is_integer(rows) ->
        rows

      _ ->
        status
        |> get_in(["result", "pages"])
        |> List.wrap()
        |> Enum.reduce(0, &(&2 + (&1["numRows"] || 0)))
    end
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp page_ids(status) do
    status
    |> get_in(["result", "pages"])
    |> List.wrap()
    |> Enum.map(& &1["id"])
  end

  # Druid answers an empty page with an empty body on some versions
  defp rows(rows) when is_list(rows), do: rows
  defp rows(""), do: []
  defp rows(nil), do: []
end
