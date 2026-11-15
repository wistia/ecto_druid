defmodule Druid.Client.Metadata do
  @moduledoc """
  Builds requests for the metadata store and segment loading parts of
  Druid's [legacy metadata API](https://druid.apache.org/docs/latest/api-reference/legacy-metadata-api).

  Unlike `Druid.Client.DataSource`, which sees only loaded segments, these
  requests read the metadata store, so they cover every used segment and,
  when asked, unused ones. The API is served by the Coordinator, so send
  these requests to the Router or Coordinator.

  Druid recommends querying the `sys` tables with SQL where they cover what
  you need.
  """

  import Druid.Client.Util, only: [params: 2, path: 2]

  @coordinator_path "/druid/coordinator/v1"
  @metadata_path @coordinator_path <> "/metadata"

  @doc """
  Builds a request to list the names of data sources with used segments.

  ## Options

    * `:include_unused` - When `true`, also list data sources with only
      unused segments.
    * `:full` - When `true`, return each data source's segments.
  """
  @spec data_sources(Keyword.t()) :: Req.Request.t()
  def data_sources(opts \\ []) do
    get(
      @metadata_path <> "/datasources",
      params(opts, include_unused: "includeUnused", full: "full")
    )
  end

  @doc """
  Builds a request to get a data source and its used segments.
  """
  @spec data_source(String.t()) :: Req.Request.t()
  def data_source(data_source) do
    get(path(@metadata_path <> "/datasources", [data_source]), [])
  end

  @doc """
  Builds a request to list the used segments of every data source.

  ## Options

    * `:data_sources` - Only segments of these data sources.
    * `:include_overshadowed_status` - When `true`, also return whether each
      segment is overshadowed.
    * `:include_realtime_segments` - When `true`, also return segments still
      being ingested.
  """
  @spec segments(Keyword.t()) :: Req.Request.t()
  def segments(opts \\ []) do
    data_sources = for name <- Keyword.get(opts, :data_sources, []), do: {"datasources", name}

    params =
      data_sources ++
        params(opts,
          include_overshadowed_status: "includeOvershadowedStatus",
          include_realtime_segments: "includeRealtimeSegments"
        )

    get(@metadata_path <> "/segments", params)
  end

  @doc """
  Builds a request to list the IDs of a data source's used segments.

  ## Options

    * `:full` - When `true`, return each segment's metadata.
  """
  @spec data_source_segments(String.t(), Keyword.t()) :: Req.Request.t()
  def data_source_segments(data_source, opts \\ []) do
    get(
      path(@metadata_path <> "/datasources", [data_source, "segments"]),
      params(opts, full: "full")
    )
  end

  @doc """
  Builds a request to get a used segment's metadata.

  ## Options

    * `:include_unused` - When `true`, also find the segment if it is unused.
  """
  @spec segment(String.t(), String.t(), Keyword.t()) :: Req.Request.t()
  def segment(data_source, segment_id, opts \\ []) do
    get(
      path(@metadata_path <> "/datasources", [data_source, "segments", segment_id]),
      params(opts, include_unused: "includeUnused")
    )
  end

  @doc """
  Builds a request to get the percentage of each data source's segments that
  are loaded.

  ## Options

    * `:simple` - When `true`, return the number of segments left to load per
      data source instead.
    * `:full` - When `true`, return the number of replicas left to load per
      tier and data source instead.
  """
  @spec load_status(Keyword.t()) :: Req.Request.t()
  def load_status(opts \\ []) do
    get(@coordinator_path <> "/loadstatus", params(opts, simple: "simple", full: "full"))
  end

  @doc """
  Builds a request to list the segments each Historical has queued to load or
  drop.

  ## Options

    * `:simple` - When `true`, return counts and sizes instead of segment IDs.
    * `:full` - When `true`, return each segment's metadata.
  """
  @spec load_queue(Keyword.t()) :: Req.Request.t()
  def load_queue(opts \\ []) do
    get(@coordinator_path <> "/loadqueue", params(opts, simple: "simple", full: "full"))
  end

  @doc """
  Builds a request to list the data servers the Coordinator knows about.

  ## Options

    * `:simple` - When `true`, also return each server's type, tier, size,
      and capacity.
  """
  @spec servers(Keyword.t()) :: Req.Request.t()
  def servers(opts \\ []) do
    get(@coordinator_path <> "/servers", params(opts, simple: "simple"))
  end

  defp get(url, params), do: Req.new(method: :get, url: url, params: params)
end
