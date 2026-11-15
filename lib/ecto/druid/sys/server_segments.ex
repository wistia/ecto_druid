defmodule Ecto.Druid.Sys.ServerSegments do
  @moduledoc """
  The `sys.server_segments` table: which server serves which segment.

  Join it with `Ecto.Druid.Sys.Servers` and `Ecto.Druid.Sys.Segments`:

      from ss in Ecto.Druid.Sys.ServerSegments,
        join: s in Ecto.Druid.Sys.Segments, on: s.segment_id == ss.segment_id,
        group_by: [ss.server, s.datasource],
        select: %{server: ss.server, datasource: s.datasource, segments: count()}

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#server_segments-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "sys"
  schema "server_segments" do
    field :server, :string
    field :segment_id, :string
  end
end
