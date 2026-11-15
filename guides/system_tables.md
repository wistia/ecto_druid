# System Tables

Druid's metadata tables have ready-made schemas:

* `sys`: `Ecto.Druid.Sys.Segments`, `Ecto.Druid.Sys.ServerSegments`,
  `Ecto.Druid.Sys.Servers`, `Ecto.Druid.Sys.ServerProperties`,
  `Ecto.Druid.Sys.Tasks` and `Ecto.Druid.Sys.Supervisors`
* `INFORMATION_SCHEMA`: `Ecto.Druid.InformationSchema.Schemata`,
  `Ecto.Druid.InformationSchema.Tables`, `Ecto.Druid.InformationSchema.Columns`
  and `Ecto.Druid.InformationSchema.Routines`

Query them like any other schema:

```elixir
import Ecto.Query

MyApp.DruidRepo.all(
  from s in Ecto.Druid.Sys.Segments,
    where: s.datasource == "page_views_hourly" and s.is_active == 1,
    select: %{segment_id: s.segment_id, size: s.size, num_rows: s.num_rows}
)

MyApp.DruidRepo.all(
  from c in Ecto.Druid.InformationSchema.Columns,
    where: c.table_schema == "druid" and c.table_name == "page_views_hourly",
    order_by: c.ordinal_position,
    select: {c.column_name, c.data_type}
)
```

Flags such as `is_active` are 0/1 integers, as Druid types them. Columns
holding JSON (a segment's `shard_spec`, a supervisor's `spec`) load as maps
(see `Ecto.Druid.JSON`).
