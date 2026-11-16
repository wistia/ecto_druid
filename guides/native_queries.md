# Native Queries

Druid also has a [native JSON query language](https://druid.apache.org/docs/latest/querying/),
which Druid SQL is translated into. Use it for query types or options SQL
doesn't expose.

## Sending a native query

`native_query/2` on the repo sends a query map to the same host and returns
the decoded JSON response, with string keys:

```elixir
MyApp.DruidRepo.native_query(%{
  queryType: "topN",
  dataSource: "wikipedia",
  intervals: ["2016-06-27/2016-06-28"],
  granularity: "all",
  dimension: "channel",
  metric: "edits",
  threshold: 10,
  aggregations: [%{type: "count", name: "edits"}],
  context: %{timeout: 30_000}
})
#=> [%{"timestamp" => "2016-06-27T00:00:00.000Z",
#      "result" => [%{"channel" => "#en.wikipedia", "edits" => 6650}, ...]}]
```

An `Ecto.Druid.Interval` encodes to its ISO 8601 string, so you can also write
`intervals: [Ecto.Druid.Interval.last(day: 1)]`.

A native query carries its context in the query map, so the repo's
`:context` config doesn't apply.

## Flattening results

Each query type nests its results differently. `Ecto.Druid.Native.rows/3`
flattens `timeseries`, `topN`, `groupBy` and `scan` results into one map per
row, given the query that produced them:

```elixir
query
|> MyApp.DruidRepo.native_query()
|> Ecto.Druid.Native.rows(query)
#=> [%{"__time" => "2016-06-27T00:00:00.000Z", "channel" => "#en.wikipedia", "edits" => 6650}, ...]
```

`"__time"` holds each row's time bucket. This also names the values of
`groupBy` results with the `resultAsArray` context flag and of `scan` results
in the `compactedList` format.

## Seeing the native query for an Ecto query

To debug an Ecto query, or to look up how Druid expresses something in native
form, `to_native/2` asks Druid for the native query it plans the query into
(with `EXPLAIN PLAN FOR`), using the same params and `:context` as running it
would:

```elixir
import Ecto.Query

query =
  from p in "wikipedia",
    where: p.channel == ^"#en.wikipedia",
    group_by: p.page,
    select: {p.page, sum(p.added)}

MyApp.DruidRepo.to_native(query)
#=> %{"queryType" => "groupBy",
#     "dataSource" => %{"type" => "table", "name" => "wikipedia"},
#     "filter" => %{"type" => "equals", "column" => "channel", "matchValue" => "#en.wikipedia", ...},
#     "dimensions" => [%{"type" => "default", "dimension" => "page", "outputName" => "d0", ...}],
#     "aggregations" => [%{"type" => "longSum", "name" => "a0", "fieldName" => "added"}],
#     "context" => %{...},
#     ...}
```

Druid names the planned columns `d0`, `d1`, … for dimensions, `a0`, `a1`, …
for aggregations and `p0`, `p1`, … for post-aggregations. The plan is written
for Druid's SQL layer, with an eternity interval and planner context keys such
as `timestampResultField`, so treat it as a reference for writing your own
native query rather than one to send as is.

## Inspecting and canceling queries

`Druid.Client.Native` also builds requests to list the segments a native query
would read (`candidates/1`) and to cancel a running query by its `queryId`
(`cancel/1`).
