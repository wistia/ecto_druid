defmodule WikiExplorer.Cluster do
  @moduledoc """
  What Druid knows about the `wiki_edits` data source, read from its system
  tables with the schemas ecto_druid ships (`Ecto.Druid.Sys.*` and
  `Ecto.Druid.InformationSchema.*`).
  """
  import Ecto.Query

  alias Ecto.Druid.InformationSchema.Columns
  alias Ecto.Druid.Sys.{Segments, Servers}
  alias WikiExplorer.DruidRepo
  alias WikiExplorer.Wiki.ChannelLanguages

  @data_source "wiki_edits"

  def data_source, do: @data_source

  @doc "The data source's columns and their Druid SQL types."
  def columns do
    DruidRepo.all(
      from c in Columns,
        where: c.table_schema == "druid" and c.table_name == @data_source,
        order_by: c.ordinal_position,
        select: %{name: c.column_name, type: c.data_type}
    )
  end

  @doc "The data source's published segments."
  def segments do
    DruidRepo.all(
      from s in Segments,
        where: s.datasource == @data_source and s.is_published == 1,
        order_by: [s.start, s.partition_num],
        select: %{
          segment_id: s.segment_id,
          start: s.start,
          end: s.end,
          size: s.size,
          num_rows: s.num_rows,
          is_available: s.is_available == 1
        }
    )
  end

  @doc "The services in the cluster."
  def servers do
    DruidRepo.all(
      from s in Servers,
        order_by: [s.server_type, s.server],
        select: %{server: s.server, type: s.server_type, tier: s.tier, curr_size: s.curr_size}
    )
  end

  @doc """
  Every entry in the `channel_languages` lookup, read like a table. Druid
  can't sort a lookup by its key, so it's sorted here.
  """
  def channel_languages do
    ChannelLanguages
    |> DruidRepo.all()
    |> Enum.sort_by(& &1.channel)
  end
end
