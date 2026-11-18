defmodule Ecto.Adapters.Druid.Telemetry do
  @moduledoc false

  # The repo's query event and query log, shaped like the ones
  # Ecto.Adapters.SQL emits, so handlers written for SQL repos (metrics,
  # tracing, LiveDashboard) work with Druid repos too. See "Telemetry" in
  # Ecto.Adapters.Druid.

  require Logger

  @decode_time {__MODULE__, :decode_time}

  @doc """
  Runs `fun`, which sends one query to Druid, then emits the repo's query
  event and logs the query.

  `info` is the event metadata, without `:result`, `:cast_params`,
  `:stacktrace` or `:options`, plus the repo `:config`. `opts` are the
  options given to the repo call. `fun` returns `{value, result}`: `value`
  is returned, and `result` is `{:ok, %{num_rows: n, rows: rows}}` or
  `{:error, exception}` for the event. If `fun` raises, the event gets
  `{:error, exception}` and the exception is reraised.
  """
  @spec query(map(), Keyword.t(), (-> {term, {:ok, map()} | {:error, Exception.t()}})) :: term
  def query(info, opts, fun) do
    stacktrace = stacktrace(opts, info.config)
    previous = Process.put(@decode_time, 0)
    start = System.monotonic_time()

    try do
      fun.()
    rescue
      exception ->
        emit(info, opts, stacktrace, start, {:error, exception})
        reraise exception, __STACKTRACE__
    else
      {value, result} ->
        emit(info, opts, stacktrace, start, result)
        value
    after
      if previous, do: Process.put(@decode_time, previous), else: Process.delete(@decode_time)
    end
  end

  @doc """
  Sends a request like `Druid.Client.request!/2`, counting the time spent
  decoding its response toward the running query's `:decode_time`.
  """
  @spec request!(Req.Request.t(), Keyword.t()) :: term
  def request!(request, opts) do
    {body, decode_time} = Druid.Client.timed_request!(request, opts)
    add_decode_time(decode_time)
    body
  end

  @doc """
  Like `request!/2`, but returns `{:ok, body}` or `{:error, exception}` as
  `Druid.Client.request/2` does.
  """
  @spec request(Req.Request.t(), Keyword.t()) :: {:ok, term} | {:error, Exception.t()}
  def request(request, opts) do
    {:ok, request!(request, opts)}
  rescue
    error -> {:error, error}
  end

  @doc """
  Runs `fun`, counting its time toward the running query's `:decode_time`.
  """
  @spec decode((-> result)) :: result when result: term
  def decode(fun) do
    start = System.monotonic_time()
    result = fun.()
    add_decode_time(System.monotonic_time() - start)
    result
  end

  @doc """
  Returns the `sqlQueryId` in `context`, adding one if it has none, so the
  query event can carry the ID Druid will know the query by.
  """
  @spec put_sql_query_id(map()) :: {String.t(), map()}
  def put_sql_query_id(context) do
    case context["sqlQueryId"] || context[:sqlQueryId] do
      nil ->
        query_id = Ecto.UUID.generate()
        {query_id, Map.put(context, :sqlQueryId, query_id)}

      query_id ->
        {query_id, context}
    end
  end

  @doc """
  Returns the source an Ecto query reads, as `Ecto.Adapters.SQL` reports it:
  the first source's name, or `nil` for a fragment or subquery.
  """
  @spec source(map()) :: String.t() | nil
  def source(%{sources: sources}) when tuple_size(sources) > 0 do
    case elem(sources, 0) do
      {source, _schema, _prefix} when is_binary(source) -> source
      _ -> nil
    end
  end

  def source(_query_meta), do: nil

  defp add_decode_time(time) do
    case Process.get(@decode_time) do
      nil -> :ok
      total -> Process.put(@decode_time, total + time)
    end
  end

  # Ecto puts the stacktrace in the options when the repo is configured
  # with `stacktrace: true`. native_query/2 doesn't go through Ecto, so it
  # takes it here.
  defp stacktrace(opts, config) do
    case Keyword.get(opts, :stacktrace) do
      stacktrace when is_list(stacktrace) ->
        stacktrace

      option ->
        if option || Keyword.get(config, :stacktrace, false) do
          {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
          stacktrace
        end
    end
  end

  defp emit(info, opts, stacktrace, start, result) do
    total_time = System.monotonic_time() - start
    decode_time = Process.get(@decode_time, 0)
    {config, info} = Map.pop!(info, :config)

    measurements = %{
      query_time: total_time - decode_time,
      decode_time: decode_time,
      total_time: total_time
    }

    metadata =
      Map.merge(info, %{
        result: result,
        cast_params: Keyword.get(opts, :cast_params),
        stacktrace: stacktrace,
        options: Keyword.get(opts, :telemetry_options, [])
      })

    if event = Keyword.get(opts, :telemetry_event, event(config)) do
      :telemetry.execute(event, measurements, metadata)
    end

    log(config, opts, measurements, metadata)
  end

  defp event(config) do
    case Keyword.get(config, :telemetry_prefix) do
      nil -> nil
      prefix -> prefix ++ [:query]
    end
  end

  # The same rules as Ecto.Adapters.SQL: `log: false` on the call or in the
  # repo config turns logging off, and a level on the call wins.
  defp log(config, opts, measurements, metadata) do
    case {Keyword.get(opts, :log), Keyword.get(config, :log, :debug)} do
      {false, _level} -> :ok
      {opts_level, false} when opts_level in [nil, true] -> :ok
      {true, level} -> log(level, measurements, metadata)
      {opts_level, level} -> log(opts_level || level, measurements, metadata)
    end
  end

  defp log(level, measurements, metadata) do
    Logger.log(level, fn -> log_iodata(measurements, metadata) end)
  end

  defp log_iodata(measurements, metadata) do
    [
      "QUERY",
      ?\s,
      log_result(metadata.result),
      log_source(metadata.source),
      log_time("db", measurements.query_time, true),
      log_time("decode", measurements.decode_time, false),
      ?\n,
      metadata.query,
      log_params(metadata),
      log_stacktrace(metadata.stacktrace, metadata.repo)
    ]
  end

  defp log_result({:ok, _result}), do: "OK"
  defp log_result({:error, _error}), do: "ERROR"

  defp log_source(nil), do: ""
  defp log_source(source), do: [" source=", inspect(source)]

  defp log_time(label, time, force?) do
    us = System.convert_time_unit(time, :native, :microsecond)

    if force? or us > 1000 do
      [?\s, label, ?=, :io_lib_format.fwrite_g(div(us, 100) / 10), "ms"]
    else
      []
    end
  end

  # Native queries carry their values inline, so they have no params
  defp log_params(%{params: nil}), do: []

  defp log_params(%{cast_params: cast_params, params: params}) do
    params = cast_params || Enum.map(params, &param_value/1)
    [?\s, inspect(params, charlists: false)]
  end

  defp param_value(%{value: value}), do: value
  defp param_value(value), do: value

  # Points at the caller, as Ecto.Adapters.SQL does: the frame just before
  # the first call into the repo or Ecto, walking in from the outermost one.
  defp log_stacktrace([_ | _] = stacktrace, repo) do
    case last_caller(Enum.reverse(stacktrace), repo, nil) do
      {module, function, arity, info} ->
        [?\n, "↳ ", Exception.format_mfa(module, function, arity), log_location(info)]

      nil ->
        []
    end
  end

  defp log_stacktrace(_stacktrace, _repo), do: []

  @repo_modules [
    Ecto.Repo.Queryable,
    Ecto.Repo.Schema,
    Ecto.Repo.Transaction,
    Ecto.Adapters.Druid
  ]

  defp last_caller([{module, _fun, _arity, _info} | _stacktrace], repo, last)
       when module == repo or module in @repo_modules,
       do: last

  defp last_caller([frame | stacktrace], repo, _last), do: last_caller(stacktrace, repo, frame)
  defp last_caller([], _repo, last), do: last

  defp log_location(info) do
    case {Keyword.get(info, :file), Keyword.get(info, :line)} do
      {nil, _line} -> []
      {file, nil} -> [", at: ", to_string(file)]
      {file, line} -> [", at: ", to_string(file), ?:, Integer.to_string(line)]
    end
  end
end
