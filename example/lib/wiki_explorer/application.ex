defmodule WikiExplorer.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WikiExplorerWeb.Telemetry,
      WikiExplorer.DruidRepo,
      {DNSCluster, query: Application.get_env(:wiki_explorer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WikiExplorer.PubSub},
      # Start a worker by calling: WikiExplorer.Worker.start_link(arg)
      # {WikiExplorer.Worker, arg},
      # Start to serve requests, typically the last entry
      WikiExplorerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WikiExplorer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WikiExplorerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
