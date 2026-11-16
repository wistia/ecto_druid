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
  * `:context` - A map of default [SQL query context parameters](https://druid.apache.org/docs/latest/querying/sql-query-context)
    sent with every query, for example `%{sqlTimeZone: "America/New_York"}`.
  * `:deep_storage` - Send every query from this repo through Druid's query
    from deep storage API. See below.

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

  ## SQL query context

  Druid accepts [query context parameters](https://druid.apache.org/docs/latest/querying/query-context-reference)
  that tune how a query runs (`timeout`, `sqlTimeZone`, `useApproximateTopN`,
  `useLexicographicTopN`, `realtimeSegmentsMode`, and so on). You can set them:

  * per repo, with the `:context` configuration option above, or
  * per query, with the `:context` option on any repo call:

        MyApp.Repo.all(query, context: %{sqlTimeZone: "America/New_York"})

  Per-query values override repo config values, which override the adapter
  defaults. Native queries (`native_query/2`) carry their context inline in the
  query map instead.
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable

  @impl Ecto.Adapter
  defmacro __before_compile__(_env) do
    quote do
      def to_sql(query) do
        Ecto.Adapters.SQL.to_sql(:all, get_dynamic_repo(), query)
      end

      def native_query(query, opts \\ []) do
        Ecto.Adapters.Druid.native_query(get_dynamic_repo(), query, opts)
      end

      # TODO: Implement insert_all
      # def insert_all(schema_or_source, entries, opts \\ []) do
      #   repo = get_dynamic_repo()

      #   Ecto.Repo.Schema.insert_all(
      #     __MODULE__,
      #     repo,
      #     schema_or_source,
      #     entries,
      #     Ecto.Repo.Supervisor.tuplet(repo, prepare_opts(:insert_all, opts))
      #   )
      # end
    end
  end

  @impl Ecto.Adapter
  def ensure_all_started(config, _type) do
    {:ok, [config]}
  end

  @impl Ecto.Adapter
  def init(config) do
    finch_opts =
      Keyword.get(config, :finch_opts, [])
      |> Keyword.put(:name, __MODULE__.Finch)

    {:ok, Supervisor.child_spec({Finch, finch_opts}, []), %{config: config}}
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

      _ ->
        raise RuntimeError, "Unsupported query kind: #{inspect(kind)}"
    end
  end

  @impl Ecto.Adapter.Queryable
  def execute(adapter_meta, _query_meta, query, params, opts) do
    {sql, params, request_opts} = request(adapter_meta, query, params, opts)

    values =
      case __MODULE__.Statement.options(request_opts) do
        nil -> broker_query(sql, params, request_opts)
        deep_storage -> __MODULE__.Statement.all(sql, params, deep_storage, request_opts)
      end

    {Enum.count(values), values}
  end

  @impl Ecto.Adapter.Queryable
  def stream(adapter_meta, _query_meta, query, params, opts) do
    {sql, params, request_opts} = request(adapter_meta, query, params, opts)

    case __MODULE__.Statement.options(request_opts) do
      nil ->
        # The Broker sends every row in one response, so this is one chunk,
        # but it is still not sent until the stream is enumerated
        Stream.flat_map([nil], fn nil ->
          values = broker_query(sql, params, request_opts)
          [{Enum.count(values), values}]
        end)

      deep_storage ->
        __MODULE__.Statement.stream(sql, params, deep_storage, request_opts)
    end
  end

  defp request(%{config: config}, query, params, opts) do
    params = Enum.map(params, &__MODULE__.Types.to_db/1)
    opts = merge_context(config, opts)
    request_opts = config |> Keyword.merge(opts) |> Keyword.put(:finch, __MODULE__.Finch)
    {prepared_sql(query), params, request_opts}
  end

  defp prepared_sql({:cache, _update, {_id, sql}}), do: sql
  defp prepared_sql({:cached, _update, _reset, {_id, sql}}), do: sql
  defp prepared_sql({:nocache, {_id, sql}}), do: sql

  defp broker_query(sql, params, request_opts) do
    Druid.Client.SQL.query(sql, params, request_opts)
    |> Druid.Client.request!(request_opts)
  end

  @doc false
  def merge_context(config, opts) do
    context =
      config
      |> Keyword.get(:context, %{})
      |> Map.merge(Keyword.get(opts, :context, %{}))

    Keyword.put(opts, :context, context)
  end

  @doc false
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

  @doc false
  def native_query(repo, query, opts) do
    request_opts = repo.config() |> Keyword.merge(opts) |> Keyword.put(:finch, __MODULE__.Finch)

    Druid.Client.Native.query(query)
    |> Druid.Client.request!(request_opts)
  end
end
