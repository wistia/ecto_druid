defmodule Druid.Client.DataSource do
  @moduledoc """
  Builds requests to inspect data sources and manage their segments.

  Inspection requests use the Coordinator's [legacy metadata API](https://druid.apache.org/docs/latest/api-reference/legacy-metadata-api),
  which covers only data sources with segments loaded on Historicals. Segment
  management uses the Overlord's [data management API](https://druid.apache.org/docs/latest/api-reference/data-management-api).
  Send these requests to the Router.

  Intervals are ISO 8601 strings such as `"2024-01-01/2024-02-01"`.

  ## Examples

      Druid.Client.DataSource.list()
      |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.DataSource.mark_unused("wikipedia", %{"interval" => "2015-09-12/2015-09-13"})
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """

  import Druid.Client.Util, only: [params: 2, path: 2, path_interval: 1]

  @coordinator_path "/druid/coordinator/v1/datasources"
  @overlord_path "/druid/indexer/v1/datasources"

  @detail [simple: "simple", full: "full"]

  @doc """
  Builds a request to list the names of the data sources with loaded
  segments.

  ## Options

    * `:simple` - When `true`, also return each data source's segment count
      and size.
    * `:full` - When `true`, return each data source's loaded segments.
  """
  @spec list(Keyword.t()) :: Req.Request.t()
  def list(opts \\ []) do
    Req.new(method: :get, url: @coordinator_path, params: params(opts, @detail))
  end

  @doc """
  Builds a request to get a summary of a data source's loaded segments.

  ## Options

    * `:full` - When `true`, return the data source's loaded segments.
  """
  @spec get(String.t(), Keyword.t()) :: Req.Request.t()
  def get(data_source, opts \\ []) do
    coordinator(data_source, [], params(opts, full: "full"))
  end

  @doc """
  Builds a request to list the intervals of a data source's loaded segments,
  newest first.

  ## Options

    * `:simple` - When `true`, also return each interval's segment count and
      size.
    * `:full` - When `true`, return each interval's segments.
  """
  @spec intervals(String.t(), Keyword.t()) :: Req.Request.t()
  def intervals(data_source, opts \\ []) do
    coordinator(data_source, ["intervals"], params(opts, @detail))
  end

  @doc """
  Builds a request to list the IDs of a data source's loaded segments within
  an interval. Takes the same options as `intervals/2`.
  """
  @spec interval(String.t(), Druid.Interval.t() | String.t(), Keyword.t()) :: Req.Request.t()
  def interval(data_source, interval, opts \\ []) do
    coordinator(data_source, ["intervals", path_interval(interval)], params(opts, @detail))
  end

  @doc """
  Builds a request to list the IDs of a data source's loaded segments.

  ## Options

    * `:full` - When `true`, return each segment's metadata and servers.
  """
  @spec segments(String.t(), Keyword.t()) :: Req.Request.t()
  def segments(data_source, opts \\ []) do
    coordinator(data_source, ["segments"], params(opts, full: "full"))
  end

  @doc """
  Builds a request to get a loaded segment's metadata and servers.
  """
  @spec segment(String.t(), String.t()) :: Req.Request.t()
  def segment(data_source, segment_id) do
    coordinator(data_source, ["segments", segment_id], [])
  end

  @doc """
  Builds a request to list the tiers that hold a data source's segments.
  """
  @spec tiers(String.t()) :: Req.Request.t()
  def tiers(data_source) do
    coordinator(data_source, ["tiers"], [])
  end

  @doc """
  Builds a request to get the percentage of a data source's segments that are
  loaded. When no used segments match, Druid responds with a text message
  instead.

  ## Options

    * `:force_metadata_refresh` - When `true`, reread used segments from the
      metadata store first. Defaults to `false`.
    * `:interval` - Only consider segments in this interval.
    * `:simple` - When `true`, return the number of segments left to load
      instead.
    * `:full` - When `true`, return the number of replicas left to load per
      tier instead.
  """
  @spec load_status(String.t(), Keyword.t()) :: Req.Request.t()
  def load_status(data_source, opts \\ []) do
    params =
      [{"forceMetadataRefresh", Keyword.get(opts, :force_metadata_refresh, false)}] ++
        params(opts, [interval: "interval"] ++ @detail)

    coordinator(data_source, ["loadstatus"], params)
  end

  @doc """
  Builds a request to mark segments as used, so Historicals load them.

  With no `selector`, marks every unused segment that is not overshadowed.
  Otherwise `selector` is either `%{"interval" => interval}`, optionally with
  `"versions"`, or `%{"segmentIds" => ids}`.

  Druid responds with `%{"numChangedSegments" => count}`.
  """
  @spec mark_used(String.t(), map() | nil) :: Req.Request.t()
  def mark_used(data_source, selector \\ nil)

  def mark_used(data_source, nil), do: overlord(:post, data_source, [])

  def mark_used(data_source, selector) do
    overlord(:post, data_source, ["markUsed"], json: selector)
  end

  @doc """
  Builds a request to mark segments as unused, so Historicals drop them. The
  segments stay in deep storage until `kill/2` deletes them.

  With no `selector`, marks every segment of the data source. Otherwise
  `selector` takes the same form as in `mark_used/2`.

  Druid responds with `%{"numChangedSegments" => count}`.
  """
  @spec mark_unused(String.t(), map() | nil) :: Req.Request.t()
  def mark_unused(data_source, selector \\ nil)

  def mark_unused(data_source, nil), do: overlord(:delete, data_source, [])

  def mark_unused(data_source, selector) do
    overlord(:post, data_source, ["markUnused"], json: selector)
  end

  @doc """
  Builds a request to mark one segment as used. Druid responds with
  `%{"segmentStateChanged" => boolean}`.
  """
  @spec mark_segment_used(String.t(), String.t()) :: Req.Request.t()
  def mark_segment_used(data_source, segment_id) do
    overlord(:post, data_source, ["segments", segment_id])
  end

  @doc """
  Builds a request to mark one segment as unused. Druid responds with
  `%{"segmentStateChanged" => boolean}`.
  """
  @spec mark_segment_unused(String.t(), String.t()) :: Req.Request.t()
  def mark_segment_unused(data_source, segment_id) do
    overlord(:delete, data_source, ["segments", segment_id])
  end

  @doc """
  Builds a request to submit a `kill` task that permanently deletes a data
  source's unused segments within an interval, from both the metadata store
  and deep storage. This cannot be undone.
  """
  @spec kill(String.t(), Druid.Interval.t() | String.t()) :: Req.Request.t()
  def kill(data_source, interval) do
    Req.new(
      method: :delete,
      url: path(@coordinator_path, [data_source, "intervals", path_interval(interval)])
    )
  end

  defp coordinator(data_source, segments, params) do
    Req.new(
      method: :get,
      url: path(@coordinator_path, [data_source | segments]),
      params: params
    )
  end

  defp overlord(method, data_source, segments, opts \\ []) do
    Req.new([method: method, url: path(@overlord_path, [data_source | segments])] ++ opts)
  end
end
