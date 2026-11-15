defmodule Druid.Client.Compaction do
  @moduledoc """
  Builds requests for Druid's [automatic compaction API](https://druid.apache.org/docs/latest/api-reference/automatic-compaction-api).

  These requests manage compaction run by the Coordinator. To run compaction
  as an `autocompact` supervisor instead, see `Druid.Client.Supervisor` and
  `Druid.Supervisors`. Send these requests to the Router.

  ## Examples

      Druid.Client.Compaction.set(%{"dataSource" => "wikipedia", "skipOffsetFromLatest" => "PT1H"})
      |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.Compaction.status(data_source: "wikipedia")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """

  import Druid.Client.Util, only: [params: 2, path: 2]

  @config_path "/druid/coordinator/v1/config/compaction"
  @cluster_path "/druid/indexer/v1/compaction/config/cluster"

  @doc """
  Builds a request to get the cluster's compaction settings and every data
  source's compaction config.
  """
  @spec all() :: Req.Request.t()
  def all, do: Req.new(method: :get, url: @config_path)

  @doc """
  Builds a request to get a data source's compaction config.
  """
  @spec get(String.t()) :: Req.Request.t()
  def get(data_source) do
    Req.new(method: :get, url: path(@config_path, [data_source]))
  end

  @doc """
  Builds a request to create or replace a data source's compaction config.
  `config` must include `"dataSource"`.
  """
  @spec set(map()) :: Req.Request.t()
  def set(config) do
    Req.new(method: :post, url: @config_path, json: config)
  end

  @doc """
  Builds a request to remove a data source's compaction config, which stops
  automatic compaction for it.
  """
  @spec delete(String.t()) :: Req.Request.t()
  def delete(data_source) do
    Req.new(method: :delete, url: path(@config_path, [data_source]))
  end

  @doc """
  Builds a request to get the history of a data source's compaction config,
  newest first.

  ## Options

    * `:count` - Return at most this many entries.
    * `:interval` - Return entries within this ISO 8601 interval.
  """
  @spec history(String.t(), Keyword.t()) :: Req.Request.t()
  def history(data_source, opts \\ []) do
    Req.new(
      method: :get,
      url: path(@config_path, [data_source, "history"]),
      params: params(opts, count: "count", interval: "interval")
    )
  end

  @doc """
  Builds a request to get how many bytes of a data source are still waiting
  to be compacted. Druid responds with a 404 for a data source without a
  compaction config.
  """
  @spec progress(String.t()) :: Req.Request.t()
  def progress(data_source) do
    Req.new(
      method: :get,
      url: "/druid/coordinator/v1/compaction/progress",
      params: [dataSource: data_source]
    )
  end

  @doc """
  Builds a request to get the compaction status of every data source with a
  compaction config.

  ## Options

    * `:data_source` - Only this data source.
  """
  @spec status(Keyword.t()) :: Req.Request.t()
  def status(opts \\ []) do
    Req.new(
      method: :get,
      url: "/druid/coordinator/v1/compaction/status",
      params: params(opts, data_source: "dataSource")
    )
  end

  @doc """
  Builds a request to get the cluster's compaction settings, such as
  `compactionTaskSlotRatio`, `maxCompactionTaskSlots`, and `useSupervisors`.
  """
  @spec cluster() :: Req.Request.t()
  def cluster, do: Req.new(method: :get, url: @cluster_path)

  @doc """
  Builds a request to update the cluster's compaction settings.
  """
  @spec set_cluster(map()) :: Req.Request.t()
  def set_cluster(config) do
    Req.new(method: :post, url: @cluster_path, json: config)
  end
end
