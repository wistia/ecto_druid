defmodule Ecto.Adapters.Druid.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Ecto.Adapters.Druid.Worker.start_link(arg)
      # {Ecto.Adapters.Druid.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ecto.Adapters.Druid.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
