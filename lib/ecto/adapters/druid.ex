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
    # Nothing to see here, yet...
  end

  @impl Ecto.Adapter
  def ensure_all_started(config, type) do
    ecto_druid_log(:debug, "#{inspect(__MODULE__)}.ensure_all_started", %{
      "#{inspect(__MODULE__)}.ensure_all_started-params" => %{type: type, config: config}
    })

    with {:ok, _} = Application.ensure_all_started(:ecto_adapters_druid) do
      {:ok, [config]}
    end
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
  def execute(_repo, _query_meta, _query, _params, _opts) do
    {:ok, []}
  end

  @impl Ecto.Adapter.Queryable
  def stream(adapter_meta, query_meta, query_cache, params, options) do
  end
end
