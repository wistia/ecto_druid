defmodule Ecto.Adapters.Druid.Application do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Ecto.Adapters.Druid.Supervisor]
    Supervisor.start_link([], opts)
  end
end
