defmodule Druid.Client.Config do
  @moduledoc """
  Builds requests for Druid's [dynamic configuration API](https://druid.apache.org/docs/latest/api-reference/dynamic-configuration-api).

  Dynamic configs change cluster behavior without a restart:

    * `:coordinator` - How the Coordinator balances, loads, and drops
      segments, such as `maxSegmentsToMove` or `pauseCoordination`.
    * `:broker` - Settings every Broker applies, such as `queryBlocklist`
      and default `queryContext` values.
    * `:worker` - How the Overlord assigns tasks to workers and autoscales
      them.

  Send these requests to the Router.

  ## Examples

      Druid.Client.Config.get(:coordinator)
      |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.Config.set(:coordinator, %{"maxSegmentsToMove" => 100}, comment: "move faster")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """

  import Druid.Client.Util, only: [audit_headers: 1, params: 2]

  @type kind :: :coordinator | :broker | :worker

  @doc """
  Builds a request to get a dynamic config.
  """
  @spec get(kind) :: Req.Request.t()
  def get(kind), do: Req.new(method: :get, url: config_path(kind))

  @doc """
  Builds a request to replace a dynamic config.

  ## Options

    * `:author` - Recorded in the config's audit history.
    * `:comment` - Recorded in the config's audit history.
  """
  @spec set(kind, map(), Keyword.t()) :: Req.Request.t()
  def set(kind, config, opts \\ []) do
    Req.new(
      method: :post,
      url: config_path(kind),
      headers: audit_headers(opts),
      json: config
    )
  end

  @doc """
  Builds a request to get the audit history of a dynamic config.

  ## Options

    * `:count` - Return at most this many entries.
    * `:interval` - Return entries within this ISO 8601 interval.
  """
  @spec history(kind, Keyword.t()) :: Req.Request.t()
  def history(kind, opts \\ []) do
    Req.new(
      method: :get,
      url: config_path(kind) <> "/history",
      params: params(opts, count: "count", interval: "interval")
    )
  end

  defp config_path(:coordinator), do: "/druid/coordinator/v1/config"
  defp config_path(:broker), do: "/druid/coordinator/v1/broker/config"
  defp config_path(:worker), do: "/druid/indexer/v1/worker"
end
