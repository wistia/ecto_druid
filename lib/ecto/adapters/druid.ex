defmodule Ecto.Adapters.Druid do
  @moduledoc """
  This adapter allows you to use Druid as a database with Ecto.

  ## Installation

  To use the Druid adapter, you need to add it to your `mix.exs` file:

      defp deps do
        [
          {:ecto_druid, "~> 0.6.0"}
        ]
      end

  ## Usage

  You can now use Ecto with Druid by defining a repository that uses the Druid adapter:

      defmodule MyApp.Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: Ecto.Adapters.Druid
      end

  ## Configuration

  Then you need to configure your repository to use the Druid adapter:

      config :my_app, MyApp.Repo,
        host: "localhost",
        port: 8082,
        finch_opts: [pools: %{default: [size: 10]}]

  The following options are supported:

  * `:host` - The host of the Druid server.
  * `:port` - The port of the Druid server.
  * `:scheme` - The scheme of the Druid server (http or https).
  * `:auth` - Credentials for every request, for example
    `{:basic, "user:password"}`. See "Authentication" below.
  * `:redirect_trusted` - Keep sending `:auth` when Druid redirects to
    another host. See "Authentication" below.
  * `:finch_opts` - [Options](https://hexdocs.pm/finch/Finch.html#start_link/1-options) to pass to Finch when making requests to Druid.
  * `:finch` - The name of the Finch pool the repo starts. Defaults to the
    repo's module name with `.Finch` appended, such as `MyApp.Repo.Finch`, so
    each repo has its own pool. Set it to give each instance of a dynamic repo
    its own pool.
  * `:context` - A map of default [SQL query context parameters](https://druid.apache.org/docs/latest/querying/sql-query-context)
    sent with every query, for example `%{sqlTimeZone: "America/New_York"}`.
  * `:deep_storage` - Send every query from this repo through Druid's query
    from deep storage API. See below.
  * `:log` - The level queries are logged at, or `false` to not log them.
    Defaults to `:debug`. See "Telemetry" below.

  ## Authentication

  For a cluster with Druid's [basic security](https://druid.apache.org/docs/latest/development/extensions-core/druid-basic-security)
  extension, set `:auth` in `config/runtime.exs` so the credentials come from
  the environment at boot rather than being compiled in:

      config :my_app, MyApp.Repo,
        host: "druid.example.com",
        port: 8888,
        scheme: "https",
        auth: {:basic, System.fetch_env!("DRUID_USER") <> ":" <> System.fetch_env!("DRUID_PASSWORD")}

  `:auth` takes anything `Req`'s `:auth` option does: `{:basic, userinfo}`,
  `{:bearer, token}`, `:netrc`, `{:netrc, path}`, a raw `authorization`
  header value, or a 0-arity function returning one of these. It also takes
  `{module, function, args}`, which is called on every request, for a token
  that expires:

      auth: {MyApp.DruidToken, :fetch, []}

  Repo config `:auth` is used by queries, `insert_all`, `native_query/2`,
  and `Druid.Tasks`, `Druid.Supervisors`, `Druid.Retention`, `Druid.Lookups`
  and `Druid.Compaction` (and their Mix tasks). Each of those modules' config
  sections, such as `tasks: [auth: ...]`, can override it, and so can an
  `:auth` option on any call.

  Point the repo at the Router where you can. The Coordinator and Overlord
  redirect requests to their leader, and the credentials are dropped on a
  redirect to another host unless you set `redirect_trusted: true`.

  ## Querying from deep storage

  Pass `deep_storage: true` to read segments that are only in deep storage,
  not loaded on Historicals:

      MyApp.Repo.all(query, deep_storage: true)
      MyApp.Repo.stream(query, deep_storage: [timeout: :timer.minutes(30)])

  The query runs as an asynchronous task, so it takes several seconds even
  when it's small. In place of `true`, pass a keyword list with `:timeout`
  (milliseconds or `:infinity`, default five minutes) or `:poll_interval`
  (milliseconds, default `1_000`). A query that fails or runs past its
  timeout raises `Ecto.Adapters.Druid.StatementError`, and on timeout it is
  canceled first. `Repo.stream/2` fetches one result page at a time.
  See the [Querying guide](querying.md#querying-from-deep-storage) for what
  the cluster needs.

  ## Inserting data

  `Repo.insert_all/3` runs Druid's SQL-based ingestion (`INSERT`, or
  `REPLACE` with `:overwrite`) and waits for the task to finish. It needs
  `:partitioned_by`:

      MyApp.Repo.insert_all(MyApp.PageViews, rows, partitioned_by: :day)
      MyApp.Repo.insert_all("page_views_hourly", query,
        partitioned_by: :day,
        overwrite: Ecto.Druid.Interval.new(~D[2026-11-01], ~D[2026-11-02])
      )

  Druid can't change or delete single rows, so `insert/2`, `update/2`,
  `delete/2`, `update_all/3` and `delete_all/2` raise. See the
  [SQL Ingestion guide](sql_ingestion.md) for the options.

  ## SQL query context

  Druid accepts [query context parameters](https://druid.apache.org/docs/latest/querying/query-context-reference)
  that tune how a query runs (`timeout`, `sqlTimeZone`, `useApproximateTopN`,
  `useLexicographicTopN`, `realtimeSegmentsMode`, and so on). You can set them:

  * per repo, with the `:context` configuration option above, or
  * per query, with the `:context` option on any repo call:

        MyApp.Repo.all(query, context: %{sqlTimeZone: "America/New_York"})

  Per-query values override repo config values, which override the adapter
  defaults. Native queries (`native_query/2`) carry their context inline in the
  query map instead, and take the repo's `:context` only with
  `merge_context: true`.

  Repo calls take `:receive_timeout`, how long to wait for Druid's response
  in milliseconds (`15_000` by default). On timeout, the query is canceled
  by its `sqlQueryId`, which every query gets unless its context has one,
  and the `Req.TransportError` is raised.

  ## Native queries

  `native_query/2` sends a [native JSON query](https://druid.apache.org/docs/latest/querying/)
  and returns `{:ok, rows}`, with the results flattened into one map per row
  by `Ecto.Druid.Native.rows/3`, or `{:error, Ecto.Adapters.Druid.NativeQueryError.t()}`.
  `native_query!/2` returns the rows or raises. Options:

    * `:raw` - Return Druid's decoded response as is, without flattening.
    * `:columns` - Column names for `windowOperator` results.
    * `:merge_context` - Merge the repo's `:context` config into the query's
      `context`, which wins where they overlap.
    * `:check_columns` - When `dataSource` is a schema module, raise before
      sending the query if it reads a column the schema doesn't define,
      including in an expression built with `expr/1`. Defaults to `true` for
      a schema. Pass `false` to skip the check.
    * `:receive_timeout` - How long to wait for Druid's response, in
      milliseconds. Defaults to `15_000`. On timeout, the query is canceled.

  The `dataSource` can be a schema module, which is replaced with its source
  name. Each query gets a `queryId` in its context unless it has one, which
  `Druid.Client.Native.cancel/1` takes. To see the native query Druid runs for
  an Ecto query, for debugging, use `to_native/2`. See the
  [Native Queries guide](native_queries.md).

  ## Telemetry

  Every query the repo sends to Druid emits the repo's
  `[..., :query]` event, such as `[:my_app, :repo, :query]`, with the
  measurements and metadata Ecto's SQL adapters use, plus the Druid
  `:query_id`. Each query is also logged at the repo's `:log` level. Repo
  calls take `:log`, `:telemetry_event`, `:telemetry_options` and
  `:stacktrace`. See the [Telemetry guide](telemetry.md).
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema

  alias __MODULE__.Telemetry

  @impl Ecto.Adapter
  defmacro __before_compile__(_env) do
    quote do
      def to_sql(query) do
        Ecto.Adapters.SQL.to_sql(:all, get_dynamic_repo(), query)
      end

      def native_query(query, opts \\ []) do
        Ecto.Adapters.Druid.native_query(get_dynamic_repo(), query, opts)
      end

      def native_query!(query, opts \\ []) do
        Ecto.Adapters.Druid.native_query!(get_dynamic_repo(), query, opts)
      end

      def to_native(query, opts \\ []) do
        Ecto.Adapters.Druid.to_native(get_dynamic_repo(), query, opts)
      end
    end
  end

  @impl Ecto.Adapter
  def ensure_all_started(config, _type) do
    {:ok, [config]}
  end

  @impl Ecto.Adapter
  def init(config) do
    finch = finch_name(Keyword.fetch!(config, :repo), config)
    finch_opts = config |> Keyword.get(:finch_opts, []) |> Keyword.put(:name, finch)

    {:ok, Supervisor.child_spec({Finch, finch_opts}, []), %{config: config, finch: finch}}
  end

  # Each repo runs its own Finch pool, named after the repo unless the config
  # names it with :finch
  @doc false
  def finch_name(repo, config) do
    Keyword.get_lazy(config, :finch, fn -> Module.concat(repo, Finch) end)
  end

  @impl Ecto.Adapter
  def checkout(_meta, _opts, fun) do
    fun.()
  end

  @impl Ecto.Adapter
  def checked_out?(_meta), do: false

  @impl Ecto.Adapter
  def dumpers(primitive_type, ecto_type) do
    __MODULE__.Types.dumpers(primitive_type, ecto_type)
  end

  @impl Ecto.Adapter
  def loaders(primitive_type, ecto_type) do
    __MODULE__.Types.loaders(primitive_type, ecto_type)
  end

  @impl Ecto.Adapter.Queryable
  def prepare(kind, query) do
    case kind do
      :all ->
        sql = IO.iodata_to_binary(__MODULE__.Query.all(query))
        {:cache, {System.unique_integer([:positive]), sql}}

      kind when kind in [:update_all, :delete_all] ->
        raise Ecto.QueryError,
          query: query,
          message:
            "Druid doesn't support #{kind}. To replace data, use `insert_all/3` with " <>
              "`:overwrite`. To drop it, use `Druid.Client.DataSource.mark_unused/2`"
    end
  end

  @impl Ecto.Adapter.Queryable
  def execute(adapter_meta, query_meta, query, params, opts) do
    {info, request_opts} = request(adapter_meta, query_meta, query, params, opts)
    %{query: sql, params: params} = info

    Telemetry.query(info, opts, fn ->
      values =
        case info.deep_storage do
          nil -> broker_query(sql, params, info.query_id, request_opts)
          deep_storage -> __MODULE__.Statement.all(sql, params, deep_storage, request_opts)
        end

      num_rows = Enum.count(values)
      {{num_rows, values}, {:ok, %{num_rows: num_rows, rows: values}}}
    end)
  end

  @impl Ecto.Adapter.Queryable
  def stream(adapter_meta, query_meta, query, params, opts) do
    {info, request_opts} = request(adapter_meta, query_meta, query, params, opts)
    %{query: sql, params: params} = info

    case info.deep_storage do
      nil ->
        # The Broker sends every row in one response, so this is one chunk,
        # but it is still not sent until the stream is enumerated
        Stream.flat_map([nil], fn nil ->
          Telemetry.query(info, opts, fn ->
            values = broker_query(sql, params, info.query_id, request_opts)
            num_rows = Enum.count(values)
            {[{num_rows, values}], {:ok, %{num_rows: num_rows, rows: values}}}
          end)
        end)

      # The event covers running the statement, not reading its result
      # pages, which happens as the stream is enumerated
      deep_storage ->
        await = fn await ->
          Telemetry.query(info, opts, fn ->
            status = await.()
            {status, {:ok, %{num_rows: __MODULE__.Statement.num_rows(status), rows: nil}}}
          end)
        end

        __MODULE__.Statement.stream(sql, params, deep_storage, request_opts, await)
    end
  end

  defp request(%{config: config, repo: repo, finch: finch}, query_meta, query, params, opts) do
    params = Enum.map(params, &__MODULE__.Types.to_db/1)
    opts = merge_context(config, opts)
    {query_id, context} = Telemetry.put_sql_query_id(opts[:context])
    opts = Keyword.put(opts, :context, context)
    request_opts = request_opts(config, repo, finch, opts)

    info = %{
      type: :druid_sql_query,
      repo: repo,
      config: config,
      query: prepared_sql(query),
      params: params,
      source: Telemetry.source(query_meta),
      query_id: query_id,
      context: context,
      deep_storage: __MODULE__.Statement.options(request_opts)
    }

    {info, request_opts}
  end

  # A :finch option on the call wins over the repo's pool
  @doc false
  def request_opts(config, repo, finch, opts) do
    config
    |> Keyword.put(:finch, finch)
    |> Keyword.merge(opts)
    |> Keyword.put(:telemetry_metadata, %{repo: repo})
  end

  defp prepared_sql({:cache, _update, {_id, sql}}), do: sql
  defp prepared_sql({:cached, _update, _reset, {_id, sql}}), do: sql
  defp prepared_sql({:nocache, {_id, sql}}), do: sql

  # The Broker keeps running a query after the client gives up on it, so a
  # query whose request times out is canceled before the error is reraised
  defp broker_query(sql, params, query_id, request_opts) do
    Druid.Client.SQL.query(sql, params, request_opts)
    |> Telemetry.request!(request_opts)
  rescue
    error in Req.TransportError ->
      if error.reason == :timeout, do: cancel_sql(query_id, request_opts)
      reraise error, __STACKTRACE__
  end

  @cancel_attempts 5
  @cancel_retry_delay 20

  # The Broker only knows a SQL query's id once it has started planning it,
  # so a cancel sent right after a short timeout can get a 404 for a query
  # that is about to run. Retry for a moment before giving up.
  defp cancel_sql(query_id, request_opts, attempt \\ 1) do
    case Druid.Client.request(
           Druid.Client.SQL.cancel(query_id),
           Keyword.delete(request_opts, :receive_timeout)
         ) do
      {:ok, _} ->
        true

      {:error, %Druid.Client.RequestError{status: 404}} when attempt < @cancel_attempts ->
        Process.sleep(@cancel_retry_delay)
        cancel_sql(query_id, request_opts, attempt + 1)

      {:error, _} ->
        false
    end
  end

  # Returns :ok when Druid accepted the cancel, or {:error, exception}. It
  # gets the default timeout, not the one that just ran out.
  defp cancel(request, request_opts) do
    case Druid.Client.request(request, Keyword.delete(request_opts, :receive_timeout)) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc false
  def merge_context(config, opts) do
    context =
      config
      |> Keyword.get(:context, %{})
      |> Map.merge(Keyword.get(opts, :context, %{}))

    Keyword.put(opts, :context, context)
  end

  @impl Ecto.Adapter.Schema
  def autogenerate(:id), do: nil
  def autogenerate(:embed_id), do: Ecto.UUID.generate()
  def autogenerate(:binary_id), do: Ecto.UUID.generate()

  @impl Ecto.Adapter.Schema
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
    __MODULE__.Ingest.insert_all(
      adapter_meta,
      schema_meta,
      header,
      rows,
      on_conflict,
      returning,
      placeholders,
      opts
    )
  end

  @impl Ecto.Adapter.Schema
  def insert(_adapter_meta, _schema_meta, _fields, _on_conflict, _returning, _opts) do
    raise ArgumentError,
          "Druid ingests rows in batches, so it doesn't support insert/2. Use insert_all/3"
  end

  @impl Ecto.Adapter.Schema
  def update(_adapter_meta, _schema_meta, _fields, _filters, _returning, _opts) do
    raise ArgumentError,
          "Druid doesn't support update/2. To replace data, use insert_all/3 with :overwrite"
  end

  @impl Ecto.Adapter.Schema
  def delete(_adapter_meta, _schema_meta, _filters, _returning, _opts) do
    raise ArgumentError,
          "Druid doesn't support delete/2. To drop data, use Druid.Client.DataSource.mark_unused/2"
  end

  @doc false
  def native_query(repo, query, opts) do
    {raw?, opts} = Keyword.pop(opts, :raw, false)
    {merge_context?, opts} = Keyword.pop(opts, :merge_context, false)
    {rows_opts, opts} = Keyword.split(opts, [:columns])
    {prepare_opts, opts} = Keyword.split(opts, [:check_columns])
    config = repo.config()
    %{finch: finch} = Ecto.Adapter.lookup_meta(repo)

    query =
      query
      |> Ecto.Druid.Native.prepare(prepare_opts)
      |> put_native_context(if(merge_context?, do: Keyword.get(config, :context, %{}), else: %{}))

    query_id = query["context"]["queryId"]

    request_opts = request_opts(config, repo, finch, opts)

    info = %{
      type: :druid_native_query,
      repo: repo,
      config: config,
      query: Jason.encode!(query),
      native_query: query,
      params: nil,
      source: native_source(query["dataSource"]),
      query_id: query_id,
      context: query["context"],
      deep_storage: nil
    }

    Telemetry.query(info, opts, fn ->
      case send_native_query(query, query_id, request_opts) do
        {:ok, results} ->
          results =
            if raw? or not Ecto.Druid.Native.flattens?(query),
              do: results,
              else: Telemetry.decode(fn -> Ecto.Druid.Native.rows(results, query, rows_opts) end)

          num_rows = if is_list(results), do: length(results)
          {{:ok, results}, {:ok, %{num_rows: num_rows, rows: results}}}

        {:error, error} ->
          {{:error, error}, {:error, error}}
      end
    end)
  end

  defp send_native_query(query, query_id, request_opts) do
    case Druid.Client.Native.query(query) |> Telemetry.request(request_opts) do
      {:ok, results} ->
        {:ok, results}

      # The Broker keeps running a query after the client gives up on it
      {:error, %Req.TransportError{reason: :timeout} = reason} ->
        cancel_error =
          case cancel(Druid.Client.Native.cancel(query_id), request_opts) do
            :ok -> nil
            {:error, error} -> error
          end

        {:error,
         __MODULE__.NativeQueryError.exception(
           query_id: query_id,
           reason: reason,
           canceled: is_nil(cancel_error),
           cancel_error: cancel_error
         )}

      {:error, reason} ->
        {:error, __MODULE__.NativeQueryError.exception(query_id: query_id, reason: reason)}
    end
  end

  # The table a native query reads, when it reads one table
  defp native_source(data_source) when is_binary(data_source), do: data_source
  defp native_source(%{"type" => "table", "name" => name}), do: name
  defp native_source(_data_source), do: nil

  @doc false
  def native_query!(repo, query, opts) do
    case native_query(repo, query, opts) do
      {:ok, results} -> results
      {:error, error} -> raise error
    end
  end

  # The query's own context wins over the repo's, and every query gets a
  # queryId to cancel it by.
  defp put_native_context(query, repo_context) do
    repo_context = Map.new(repo_context, fn {key, value} -> {to_string(key), value} end)

    context =
      repo_context
      |> Map.merge(query["context"] || %{})
      |> Map.put_new_lazy("queryId", &Ecto.UUID.generate/0)

    Map.put(query, "context", context)
  end

  # Druid's EXPLAIN PLAN FOR returns the native query a SQL statement plans
  # to, as a JSON list with one entry per native query it runs.
  @doc false
  def to_native(repo, queryable, opts) do
    {sql, params} = Ecto.Adapters.SQL.to_sql(:all, repo, queryable)
    sql = "EXPLAIN PLAN FOR " <> sql
    config = repo.config()
    %{finch: finch} = Ecto.Adapter.lookup_meta(repo)
    opts = merge_context(config, opts)
    {query_id, context} = Telemetry.put_sql_query_id(opts[:context])
    opts = Keyword.put(opts, :context, context)
    request_opts = request_opts(config, repo, finch, opts)
    params = Enum.map(params, &__MODULE__.Types.to_db/1)

    info = %{
      type: :druid_sql_query,
      repo: repo,
      config: config,
      query: sql,
      params: params,
      source: nil,
      query_id: query_id,
      context: context,
      deep_storage: nil
    }

    [[plan | _] | _] =
      Telemetry.query(info, opts, fn ->
        rows = broker_query(sql, params, query_id, request_opts)
        {rows, {:ok, %{num_rows: length(rows), rows: rows}}}
      end)

    case Jason.decode!(plan) do
      [%{"query" => query}] ->
        Map.update(query, "context", %{}, &Map.delete(&1, "sqlQueryId"))

      plan ->
        raise ArgumentError,
              "expected Druid to plan the query into one native query, got: #{inspect(plan)}"
    end
  end
end
