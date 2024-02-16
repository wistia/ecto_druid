defmodule Ecto.Adapters.Druid do
  @moduledoc """
  Documentation for `Ecto.Adapters.Druid`.
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable

  @impl Ecto.Adapter
  defmacro __before_compile__(_env) do
    # Nothing to see here, yet...
  end

  @impl Ecto.Adapter
  def ensure_all_started(_config, _type) do
    Application.ensure_all_started(:req)
  end

  @impl Ecto.Adapter
  def init(_config) do
    Supervisor.child_spec()
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
  def prepare(type, query) do
    {:nocache, {type, query}}
  end

  @impl Ecto.Adapter.Queryable
  def execute(_repo, _queryable, _params, _opts) do
    {:ok, []}
  end

  @impl Ecto.Adapter.Queryable
  def stream(adapter_meta, query_meta, query_cache, params, options) do
  end
end
