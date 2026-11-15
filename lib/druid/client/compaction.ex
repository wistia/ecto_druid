defmodule Druid.Client.Compaction do
  @moduledoc """
  Builds requests for Druid's [automatic compaction API](https://druid.apache.org/docs/latest/api-reference/automatic-compaction-api).

  These are the Overlord's compaction endpoints. Druid runs automatic
  compaction either as compaction supervisors or as a Coordinator duty,
  depending on the cluster's `useSupervisors` setting. These endpoints work
  in both modes: with supervisors, setting a data source's config creates or
  updates its `autocompact__<dataSource>` supervisor.

  To manage compaction configs from templates, see `Druid.Compaction`.
  """

  import Druid.Client.Util, only: [audit_headers: 1, escape: 1]

  @base_path "/druid/indexer/v1/compaction"

  @doc """
  Builds a request to get every data source's compaction config.

  Druid responds with `%{"compactionConfigs" => [config, ...]}`.

  ## Examples

      Druid.Client.Compaction.all()
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec all() :: Req.Request.t()
  def all do
    Req.new(method: :get, url: @base_path <> "/config/datasources")
  end

  @doc """
  Builds a request to get a data source's compaction config.
  """
  @spec get(String.t()) :: Req.Request.t()
  def get(data_source) do
    Req.new(method: :get, url: datasource_path(data_source))
  end

  @doc """
  Builds a request to create or replace a data source's compaction config.
  The data source is taken from the config's `"dataSource"`.

  ## Options

    * `:author` - Recorded in the config's audit history.
    * `:comment` - Recorded in the config's audit history.
  """
  @spec set(map(), Keyword.t()) :: Req.Request.t()
  def set(%{"dataSource" => data_source} = config, opts \\ []) do
    Req.new(
      method: :post,
      url: datasource_path(data_source),
      headers: audit_headers(opts),
      json: config
    )
  end

  @doc """
  Builds a request to delete a data source's compaction config, which stops
  automatic compaction of that data source.

  ## Options

    * `:author` - Recorded in the config's audit history.
    * `:comment` - Recorded in the config's audit history.
  """
  @spec delete(String.t(), Keyword.t()) :: Req.Request.t()
  def delete(data_source, opts \\ []) do
    Req.new(method: :delete, url: datasource_path(data_source), headers: audit_headers(opts))
  end

  @doc """
  Builds a request to get the audit history of a data source's compaction
  config.

  ## Options

    * `:count` - Return at most this many entries.
    * `:interval` - Return entries within this ISO 8601 interval.
  """
  @spec history(String.t(), Keyword.t()) :: Req.Request.t()
  def history(data_source, opts \\ []) do
    Req.new(
      method: :get,
      url: datasource_path(data_source) <> "/history",
      params: Keyword.take(opts, [:count, :interval])
    )
  end

  @doc """
  Builds a request to get the compaction status of every data source with a
  compaction config.

  Druid responds with `%{"latestStatus" => [status, ...]}`.
  """
  @spec statuses() :: Req.Request.t()
  def statuses do
    Req.new(method: :get, url: @base_path <> "/status/datasources")
  end

  @doc """
  Builds a request to get a data source's compaction status: how much of it
  is compacted and awaiting compaction.
  """
  @spec status(String.t()) :: Req.Request.t()
  def status(data_source) do
    Req.new(method: :get, url: @base_path <> "/status/datasources/" <> escape(data_source))
  end

  @doc """
  Builds a request to get the cluster-wide compaction config, including
  `useSupervisors`, `engine` and the task slot limits.
  """
  @spec cluster() :: Req.Request.t()
  def cluster do
    Req.new(method: :get, url: @base_path <> "/config/cluster")
  end

  @doc """
  Builds a request to update the cluster-wide compaction config, for example
  `%{"useSupervisors" => false}`.
  """
  @spec set_cluster(map()) :: Req.Request.t()
  def set_cluster(config) do
    Req.new(method: :post, url: @base_path <> "/config/cluster", json: config)
  end

  defp datasource_path(data_source),
    do: @base_path <> "/config/datasources/" <> escape(data_source)
end
