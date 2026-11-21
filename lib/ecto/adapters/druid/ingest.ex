defmodule Ecto.Adapters.Druid.Ingest do
  @moduledoc false

  # `Repo.insert_all/3` and `Repo.delete_all/2` as Druid SQL-based
  # ingestion. The statement runs as a task, which this waits for before
  # returning the number of rows written or deleted.

  alias Ecto.Adapters.Druid.{Query, Telemetry, Types}
  alias Druid.SpecTemplates

  @await_opts [:timeout, :poll_interval, :wait_for_segments]
  # Requests to the tasks API use the repo's :tasks config, like
  # Druid.Tasks, but take these from the call too
  @connection_opts [:plug, :adapter]

  def insert_all(
        adapter_meta,
        schema_meta,
        header,
        rows,
        on_conflict,
        returning,
        placeholders,
        opts
      ) do
    %{source: source, prefix: prefix} = schema_meta

    check_on_conflict!(on_conflict)

    if returning != [] do
      raise ArgumentError, ":returning is not supported by Druid"
    end

    unless Keyword.has_key?(opts, :partitioned_by) do
      raise ArgumentError,
            "Druid needs a :partitioned_by option to insert rows, such as `partitioned_by: :day`"
    end

    {rows, params} =
      case rows do
        {%Ecto.Query{} = query, params} -> {query, params}
        rows -> unzip_inserts(header, rows, placeholders)
      end

    sql = prefix |> Query.insert(source, header, rows, opts) |> IO.iodata_to_binary()

    params =
      (interval_params(Keyword.get(opts, :overwrite), :overwrite) ++ params)
      |> Enum.map(&Types.to_db/1)

    run(adapter_meta, source, sql, params, opts, fn repo, task_id, opts ->
      rows_written(repo, task_id, rows, opts)
    end)
  end

  def delete_all(adapter_meta, query, params, opts) do
    if query.joins != [] or query.with_ctes != nil or query.select != nil do
      raise Ecto.QueryError,
        query: query,
        message: "Druid's delete_all only takes a data source and where clauses"
    end

    interval =
      Keyword.get(opts, :interval) ||
        raise ArgumentError,
              "Druid deletes rows by rewriting the time chunks they're in, so delete_all " <>
                "needs an :interval to rewrite, such as `interval: \"2026-11-01/2026-11-02\"`, " <>
                "or `interval: :all`"

    unless Keyword.has_key?(opts, :partitioned_by) do
      raise ArgumentError,
            "Druid needs a :partitioned_by option to delete rows, such as `partitioned_by: :day`. " <>
              "Use the data source's segment granularity"
    end

    bounds = interval_params(interval, :interval)
    sql = query |> Query.delete_all(opts) |> IO.iodata_to_binary()
    %{source: {source, _schema}} = query.from
    params = Enum.map(bounds ++ bounds ++ params, &Types.to_db/1)

    # The task doesn't report how many rows it dropped, and Ecto needs an
    # integer, so the count is always 0
    run(adapter_meta, source, sql, params, opts, fn _, _, _ -> 0 end)
  end

  # Submits a statement as a task and waits for it. `num_rows` gives the
  # result's row count once the task succeeds.
  defp run(adapter_meta, source, sql, params, opts, num_rows) do
    %{config: config, repo: repo} = adapter_meta
    call_opts = opts
    opts = Ecto.Adapters.Druid.merge_context(config, opts)
    {query_id, context} = Telemetry.put_sql_query_id(opts[:context])
    opts = Keyword.put(opts, :context, context)

    request_opts =
      Ecto.Adapters.Druid.request_opts(config, repo, adapter_meta.finch, opts)

    info = %{
      type: :druid_sql_query,
      repo: repo,
      config: config,
      query: sql,
      params: params,
      source: source,
      query_id: query_id,
      context: context,
      deep_storage: nil
    }

    # The event covers submitting the task and waiting for it
    Telemetry.query(info, call_opts, fn ->
      %{"taskId" => task_id} =
        Druid.Client.SQL.insert(sql, params, opts)
        |> Telemetry.request!(request_opts)

      case Druid.Tasks.await(repo, task_id, Keyword.take(opts, @await_opts ++ @connection_opts)) do
        {:ok, _status} ->
          num_rows = num_rows.(repo, task_id, opts)
          {{num_rows, nil}, {:ok, %{num_rows: num_rows, rows: nil}}}

        {:error, error} ->
          raise error
      end
    end)
  end

  defp check_on_conflict!({:raise, _, []}), do: :ok

  defp check_on_conflict!(_on_conflict) do
    raise ArgumentError,
          ":on_conflict and :conflict_target are not supported by Druid, which appends rows. " <>
            "To replace data, pass :overwrite"
  end

  defp unzip_inserts(header, rows, placeholders) do
    placeholders = List.to_tuple(placeholders)

    {rows, params} =
      Enum.map_reduce(rows, [], fn fields, params ->
        Enum.map_reduce(header, params, fn key, acc ->
          case :lists.keyfind(key, 1, fields) do
            {^key, {%Ecto.Query{} = query, query_params}} ->
              {{query, length(query_params)}, Enum.reverse(query_params, acc)}

            # Druid's parameters are positional, so a placeholder's value is
            # sent once for each row that uses it
            {^key, {:placeholder, index}} ->
              value(key, elem(placeholders, index - 1), acc)

            {^key, value} ->
              value(key, value, acc)

            false ->
              {nil, acc}
          end
        end)
      end)

    {rows, Enum.reverse(params)}
  end

  # NULL is written into the SQL, since Druid needs a type for parameters
  defp value(_key, nil, acc), do: {nil, acc}
  defp value(key, value, acc), do: {key, [value | acc]}

  # The bounds of an :overwrite or :interval option, as parameters
  defp interval_params(nil, _option), do: []
  defp interval_params(:all, _option), do: []

  defp interval_params(%Ecto.Druid.Interval{start: start, stop: stop}, option),
    do: [timestamp!(start, option), timestamp!(stop, option)]

  defp interval_params({start, stop}, option),
    do: [timestamp!(start, option), timestamp!(stop, option)]

  defp interval_params(interval, option) when is_binary(interval) do
    case String.split(interval, "/") do
      [start, stop] -> [timestamp!(start, option), timestamp!(stop, option)]
      _ -> interval_error!(interval, option)
    end
  end

  defp interval_params(other, option), do: interval_error!(other, option)

  defp timestamp!(%DateTime{} = value, _option), do: value
  defp timestamp!(%NaiveDateTime{} = value, _option), do: value
  defp timestamp!(%Date{} = date, _option), do: NaiveDateTime.new!(date, ~T[00:00:00])

  defp timestamp!(string, option) when is_binary(string) do
    with {:error, _} <- datetime_from_iso8601(string),
         {:error, _} <- NaiveDateTime.from_iso8601(string),
         {:error, _} <- Date.from_iso8601(string) do
      bound_error!(string, option)
    else
      {:ok, value} -> timestamp!(value, option)
    end
  end

  defp timestamp!(other, option), do: bound_error!(other, option)

  defp datetime_from_iso8601(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      error -> error
    end
  end

  defp bound_error!(bound, option) do
    raise ArgumentError,
          "#{inspect(option)} needs an interval with date or date-time bounds, since Druid " <>
            "replaces whole time chunks, got the bound: #{inspect(bound)}"
  end

  defp interval_error!(other, option) do
    raise ArgumentError,
          "#{inspect(option)} must be :all, an Ecto.Druid.Interval, a {start, stop} tuple or " <>
            "an interval string, got: #{inspect(other)}"
  end

  # The task report counts the rows each worker wrote to segments. If it
  # can't be read, fall back to the number of rows given.
  defp rows_written(repo, task_id, rows, opts) do
    config = SpecTemplates.config(repo, :tasks, Keyword.take(opts, @connection_opts))
    request_opts = SpecTemplates.request_opts(repo, config)

    with {:ok, report} <-
           Druid.Client.Task.reports(task_id) |> Druid.Client.request(request_opts),
         %{"multiStageQuery" => %{"payload" => %{"counters" => %{} = counters}}} <- report do
      for {_stage, workers} <- counters,
          {_worker, %{"segmentGenerationProgress" => %{"rowsPushed" => pushed}}} <- workers,
          reduce: 0 do
        acc -> acc + pushed
      end
    else
      _ when is_list(rows) -> length(rows)
      _ -> 0
    end
  end
end
