defmodule WikiExplorer.Wiki do
  @moduledoc """
  Queries over the `wiki_edits` data source.

  Every query starts from `edits/1`, which applies the time filter and the
  user's filters, then adds its own grouping and aggregations. The
  `Ecto.Druid.Query` macros (`time_floor`, `approx_count_distinct_ds_hll`,
  `lookup`, and so on) compile to Druid SQL functions.
  """
  import Ecto.Query
  use Ecto.Druid.Query

  alias Ecto.Druid.Interval
  alias WikiExplorer.DruidRepo
  alias WikiExplorer.Wiki.{ChannelLanguages, Edit}

  @typedoc """
  Filters shared by the queries:

    * `:channel` - only edits in this channel, such as `"#en.wikipedia"`
    * `:page` - only edits to this page
    * `:robots` - include edits made by bots. Defaults to `true`.
  """
  @type filters :: %{
          optional(:channel) => String.t(),
          optional(:page) => String.t(),
          optional(:robots) => boolean()
        }

  @doc """
  The interval the sample data covers. Druid uses the time filter to pick
  which segments to read, so every query includes one.
  """
  def interval, do: Interval.new(~D[2016-06-27], day: 1)

  @doc "The base query: edits in `interval/0` that match the filters."
  def edits(filters \\ %{}) do
    query = from e in Edit, where: time_in_interval(e.time, ^interval())

    Enum.reduce(filters, query, fn
      {:channel, channel}, query when channel not in [nil, ""] ->
        where(query, [e], e.channel == ^channel)

      {:page, page}, query when page not in [nil, ""] ->
        where(query, [e], e.page == ^page)

      {:robots, false}, query ->
        where(query, [e], e.is_robot == "false")

      _, query ->
        query
    end)
  end

  @doc """
  Headline numbers. Distinct editors and pages are approximate, counted with
  HLL and Theta sketches.
  """
  def summary(filters \\ %{}) do
    filters
    |> summary_query()
    |> DruidRepo.one()
  end

  @doc false
  def summary_query(filters) do
    from e in edits(filters),
      select: %{
        edits: count(),
        editors: approx_count_distinct_ds_hll(e.user),
        pages: approx_count_distinct_ds_theta(e.page),
        added: coalesce(sum(e.added), 0),
        deleted: coalesce(sum(e.deleted), 0),
        median_delta: approx_quantile_ds(e.delta, 0.5),
        p90_delta: approx_quantile_ds(e.delta, 0.9)
      }
  end

  @doc """
  Edits per hour of the day. `time_floor` returns an ISO 8601 string, so the
  hour is parsed into a `DateTime` here.
  """
  def edits_by_hour(filters \\ %{}) do
    query =
      from e in edits(filters),
        group_by: time_floor(e.time, "PT1H"),
        order_by: time_floor(e.time, "PT1H"),
        select: %{
          hour: time_floor(e.time, "PT1H"),
          edits: count(),
          robot_edits: filter(count(), e.is_robot == "true")
        }

    by_hour =
      Map.new(DruidRepo.all(query), fn row ->
        {:ok, hour, 0} = DateTime.from_iso8601(row.hour)
        {hour, %{row | hour: hour}}
      end)

    # Druid only returns hours that have edits. Fill in the rest with zeros.
    for offset <- 0..23 do
      hour = DateTime.add(~U[2016-06-27 00:00:00.000Z], offset, :hour)
      Map.get(by_hour, hour, %{hour: hour, edits: 0, robot_edits: 0})
    end
  end

  @doc """
  The busiest channels, with each channel's language from the
  `channel_languages` lookup.
  """
  def top_channels(filters \\ %{}, limit \\ 10) do
    DruidRepo.all(
      from e in edits(filters),
        group_by: e.channel,
        order_by: [desc: count()],
        limit: ^limit,
        select: %{
          channel: e.channel,
          language: lookup(e.channel, ChannelLanguages, "Unknown"),
          edits: count(),
          editors: approx_count_distinct_ds_hll(e.user)
        }
    )
  end

  @doc """
  The most edited pages.

  There are tens of thousands of pages, so this sticks to cheap aggregations.
  A sketch per group (such as `approx_count_distinct_ds_hll`) across every
  page needs more merge buffer memory than a small Druid has.
  """
  def top_pages(filters \\ %{}, limit \\ 10) do
    DruidRepo.all(
      from e in edits(filters),
        group_by: [e.page, e.channel],
        order_by: [desc: count()],
        limit: ^limit,
        select: %{
          page: e.page,
          channel: e.channel,
          edits: count(),
          delta: sum(e.delta)
        }
    )
  end

  @doc "The countries anonymous edits came from (Druid geolocates their IPs)."
  def top_countries(filters \\ %{}, limit \\ 10) do
    DruidRepo.all(
      from e in edits(filters),
        where: not is_nil(e.country),
        group_by: e.country,
        order_by: [desc: count()],
        limit: ^limit,
        select: %{country: e.country, edits: count()}
    )
  end

  @doc "The editors with the most edits."
  def top_editors(filters \\ %{}, limit \\ 10) do
    DruidRepo.all(
      from e in edits(filters),
        group_by: [e.user, e.is_robot],
        order_by: [desc: count()],
        limit: ^limit,
        select: %{
          user: e.user,
          robot: e.is_robot == "true",
          edits: count(),
          added: sum(e.added),
          deleted: sum(e.deleted)
        }
    )
  end

  @doc "The most recent edits, newest first."
  def recent_edits(filters \\ %{}, limit \\ 20) do
    DruidRepo.all(
      from e in edits(filters),
        order_by: [desc: e.time],
        limit: ^limit,
        select: map(e, [:time, :user, :comment, :delta, :is_robot])
    )
  end

  @doc """
  Pages whose title contains `term`, ignoring case. `icontains_string`
  compiles to Druid's `ICONTAINS_STRING`.
  """
  def search_pages(term, filters \\ %{}, limit \\ 25) do
    DruidRepo.all(
      from e in edits(filters),
        where: icontains_string(e.page, ^term),
        group_by: [e.page, e.channel],
        order_by: [desc: count()],
        limit: ^limit,
        select: %{
          page: e.page,
          channel: e.channel,
          edits: count(),
          last_edit: max(e.time)
        }
    )
  end

  @doc "Every channel, for the filter menu."
  def channels do
    DruidRepo.all(
      from e in edits(),
        group_by: e.channel,
        order_by: e.channel,
        select: e.channel
    )
  end

  @doc """
  The top channels as a native `topN` query. Druid answers `topN` faster than
  the equivalent `GROUP BY ... ORDER BY ... LIMIT` when an approximate
  ranking is fine. The `Edit` schema stands in for its data source, and
  `check_columns: true` checks the columns the query reads against it.
  """
  def top_channels_native(limit \\ 5) do
    DruidRepo.native_query!(
      %{
        queryType: "topN",
        dataSource: Edit,
        intervals: [interval()],
        granularity: "all",
        dimension: "channel",
        metric: "edits",
        threshold: limit,
        aggregations: [
          %{type: "count", name: "edits"},
          %{type: "longSum", name: "added", fieldName: "added"}
        ]
      },
      check_columns: true
    )
  end

  @doc "The SQL and parameters a query sends to Druid."
  def to_sql(query), do: DruidRepo.to_sql(query)
end
