defmodule Ecto.Adapters.Druid do
  @moduledoc """
  Documentation for `Ecto.Adapters.Druid`.
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable

  require Logger

  def ecto_druid_log(level, message, attributes) do
    case Application.get_env(:ecto_adapters_druid, :use_logger) do
      true ->
        Logger.log(level, message, attributes)

      _ ->
        write_console_log(level, message)
    end
  end

  defp write_console_log(level, message) do
    formatted_message = format_log_message(level, message)

    {:ok, log_message} = Jason.encode(%{message: formatted_message})

    case log_in_color?() do
      true ->
        IO.ANSI.format([:normal, log_message], true) |> IO.puts()

      _ ->
        log_message |> IO.puts()
    end
  end

  defp log_in_color? do
    Application.get_env(:ecto_adapters_druid, :log_in_color, true)
  end

  defp format_log_message(level, message) do
    d = DateTime.utc_now()

    date = "#{d.year}-#{d.month}-#{d.day}"
    time = "#{d.hour}:#{d.minute}:#{d.second}"

    "#{date} #{time} UTC [Ecto Druid #{level}] #{inspect(message)}"
  end

  @impl Ecto.Adapter
  defmacro __before_compile__(_env) do
    quote do
      def to_sql(query), do: Ecto.Adapters.SQL.to_sql(:all, __MODULE__, query)
    end
  end

  @impl Ecto.Adapter
  def ensure_all_started(config, type) do
    IO.inspect([config, type], limit: :infinity, label: "Ecto.Adapters.Druid.ensure_all_started")

    ecto_druid_log(:debug, "#{inspect(__MODULE__)}.ensure_all_started", %{
      "#{inspect(__MODULE__)}.ensure_all_started-params" => %{type: type, config: config}
    })

    with {:ok, _} = Application.ensure_all_started(:req) do
      {:ok, [config]}
    end
  end

  @impl Ecto.Adapter
  def init(config) do
    IO.inspect(config, limit: :infinity, label: "Ecto.Adapters.Druid.init")

    {:ok, Supervisor.child_spec({Agent, fn -> config end}, id: __MODULE__.Agent),
     %{config: config}}
  end

  @impl Ecto.Adapter
  def checkout(meta, opts, fun) do
    IO.inspect([meta, opts, fun], limit: :infinity, label: "Ecto.Adapters.Druid.checkout")
    fun.()
  end

  @impl Ecto.Adapter
  def checked_out?(_meta), do: false

  @impl Ecto.Adapter
  def dumpers(primitive_type, ecto_type) do
    IO.inspect([primitive_type, ecto_type],
      limit: :infinity,
      label: "Ecto.Adapters.Druid.dumpers"
    )

    __MODULE__.Types.dumpers(primitive_type, ecto_type)
  end

  @impl Ecto.Adapter
  def loaders(primitive_type, ecto_type) do
    IO.inspect([primitive_type, ecto_type],
      limit: :infinity,
      label: "Ecto.Adapters.Druid.loaders"
    )

    __MODULE__.Types.loaders(primitive_type, ecto_type)
  end

  @impl Ecto.Adapter.Queryable
  def prepare(kind, query) do
    IO.inspect([kind, query], limit: :infinity, label: "Ecto.Adapters.Druid.prepare")

    case kind do
      :all ->
        sql = IO.iodata_to_binary(__MODULE__.Query.all(query))
        {:cache, {System.unique_integer([:positive]), sql}}

      _ ->
        raise RuntimeError, "Unsupported query kind: #{inspect(kind)}"
    end
  end

  @impl Ecto.Adapter.Queryable
  def execute(repo, query_meta, query, params, opts) do
    IO.inspect([repo, query_meta, query, params, opts],
      limit: :infinity,
      label: "Ecto.Adapters.Druid.execute"
    )

    {_, _, {_, sql}} = query
    params = Enum.map(params, &__MODULE__.Types.to_db/1)

    with {:ok, results} = __MODULE__.Client.execute(sql, params, Keyword.merge(repo.config, opts)) do
      {Enum.count(results), [results]}
    end
  end

  @impl Ecto.Adapter.Queryable
  def stream(_adapter_meta, _query_meta, _query_cache, _params, _opts) do
    []
  end
end
