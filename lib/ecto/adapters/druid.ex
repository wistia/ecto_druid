defmodule Ecto.Adapters.Druid do
  @moduledoc """
  Documentation for `Ecto.Adapters.Druid`.
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

      def insert_all(schema_or_source, entries, opts \\ []) do
        repo = get_dynamic_repo()

        Ecto.Repo.Schema.insert_all(
          __MODULE__,
          repo,
          schema_or_source,
          entries,
          Ecto.Repo.Supervisor.tuplet(repo, prepare_opts(:insert_all, opts))
        )
      end
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
  def execute(repo, _query_meta, query, params, opts) do
    {_, _, {_, sql}} = query
    params = Enum.map(params, &__MODULE__.Types.to_db/1)

    request_opts = repo.config |> Keyword.merge(opts) |> Keyword.put(:finch, __MODULE__.Finch)

    values =
      Druid.Client.SQL.query(sql, params, opts)
      |> Druid.Client.request!(request_opts)

    {Enum.count(values), values}
  end

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

  @impl Ecto.Adapter.Queryable
  def stream(_adapter_meta, _query_meta, _query_cache, _params, _opts) do
    []
  end

  def native_query(repo, query, opts) do
    request_opts = repo.config |> Keyword.merge(opts) |> Keyword.put(:finch, __MODULE__.Finch)

    Druid.Client.Native.query(query)
    |> Druid.Client.request!(request_opts)
  end
end
