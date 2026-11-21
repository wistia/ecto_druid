defmodule Druid.Client.Status do
  @moduledoc """
  Builds requests for Druid's [service status API](https://druid.apache.org/docs/latest/api-reference/service-status-api).

  `get/0`, `health/0`, `properties/0`, and `self_discovered/0` are served by
  every service, so they describe whichever one receives the request.
  `leader/1`, `workers/0`, and `scaling/0` can go through the Router.
  `readiness/1` and `load_status/1` must be sent to the Broker or Historical
  itself, since the Router does not forward them.

  Some of these respond with a 503 to mean "not yet", so
  `Druid.Client.request/2` returns an error until the service is ready.

  The checks (`health/0`, `self_discovered/0`, `readiness/1` and
  `load_status/1`) aren't retried, so a service that is down or not ready
  is reported as soon as it answers, not after `Req`'s retries. Pass
  `retry: :safe_transient` to `Druid.Client.request/2` to retry them.

  ## Examples

      Druid.Client.Status.health()
      |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.Status.leader(:overlord)
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """

  @doc """
  Builds a request to get the service's version and loaded extensions.
  """
  @spec get() :: Req.Request.t()
  def get, do: get("/status")

  @doc """
  Builds a request to check that the service is up. Druid responds with
  `true`.
  """
  @spec health() :: Req.Request.t()
  def health, do: check("/status/health")

  @doc """
  Builds a request to get the service's runtime properties.
  """
  @spec properties() :: Req.Request.t()
  def properties, do: get("/status/properties")

  @doc """
  Builds a request to get whether the service has registered itself with the
  cluster. Druid responds with `%{"selfDiscovered" => boolean}`.
  """
  @spec self_discovered() :: Req.Request.t()
  def self_discovered, do: check("/status/selfDiscovered/status")

  @doc """
  Builds a request to get the address of the current Coordinator or Overlord
  leader, as text.
  """
  @spec leader(:coordinator | :overlord) :: Req.Request.t()
  def leader(:coordinator), do: get("/druid/coordinator/v1/leader")
  def leader(:overlord), do: get("/druid/indexer/v1/leader")

  @doc """
  Builds a request to check that a Broker or Historical has loaded its
  segments. Druid responds with a 503 until it has.
  """
  @spec readiness(:broker | :historical) :: Req.Request.t()
  def readiness(:broker), do: check("/druid/broker/v1/readiness")
  def readiness(:historical), do: check("/druid/historical/v1/readiness")

  @doc """
  Builds a request to get whether a Broker has initialized its view of the
  cluster, or a Historical has loaded its cached segments. Druid responds
  with `%{"inventoryInitialized" => boolean}` or
  `%{"cacheInitialized" => boolean}`.
  """
  @spec load_status(:broker | :historical) :: Req.Request.t()
  def load_status(:broker), do: check("/druid/broker/v1/loadstatus")
  def load_status(:historical), do: check("/druid/historical/v1/loadstatus")

  @doc """
  Builds a request to list the Overlord's workers, with their capacity and
  running tasks.
  """
  @spec workers() :: Req.Request.t()
  def workers, do: get("/druid/indexer/v1/workers")

  @doc """
  Builds a request to get the Overlord's recent autoscaling events.
  """
  @spec scaling() :: Req.Request.t()
  def scaling, do: get("/druid/indexer/v1/scaling")

  defp get(url), do: Req.new(method: :get, url: url)

  # A check answers "no" with a 503 or by not answering, which Req would
  # retry for about seven seconds before reporting it
  defp check(url), do: Req.new(method: :get, url: url, retry: false)
end
