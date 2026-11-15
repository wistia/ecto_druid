defmodule Ecto.Druid.Sys.Segments do
  @moduledoc """
  The `sys.segments` table: one row per segment, published or served.

      from s in Ecto.Druid.Sys.Segments,
        where: s.datasource == "wikipedia" and s.is_active == 1,
        select: %{segment_id: s.segment_id, size: s.size, num_rows: s.num_rows}

  `start` and `end` are ISO 8601 strings rather than `DateTime`s, because
  segments with `ALL` granularity use bounds outside `DateTime`'s range.
  The `is_*` flags are 0/1 integers, as Druid types them. `shard_spec`,
  `dimensions`, `metrics`, `projections` and `last_compaction_state` are
  decoded from JSON (see `Ecto.Druid.JSON`).

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#segments-table)
  for what each column means.
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "sys"
  schema "segments" do
    field :segment_id, :string
    field :datasource, :string
    field :start, :string
    field :end, :string
    field :size, :integer
    field :version, :string
    field :partition_num, :integer
    field :num_replicas, :integer
    field :num_rows, :integer
    field :is_active, :integer
    field :is_published, :integer
    field :is_available, :integer
    field :is_realtime, :integer
    field :is_overshadowed, :integer
    field :shard_spec, Ecto.Druid.JSON
    field :dimensions, Ecto.Druid.JSON
    field :metrics, Ecto.Druid.JSON
    field :projections, Ecto.Druid.JSON
    field :last_compaction_state, Ecto.Druid.JSON
    field :replication_factor, :integer
  end
end
