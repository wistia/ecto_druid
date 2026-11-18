# Native Queries

Druid also has a [native JSON query language](https://druid.apache.org/docs/latest/querying/),
which Druid SQL is translated into. Use it for query types or options SQL
doesn't expose.

## Sending a native query

`native_query/2` on the repo sends a query map to the same host and returns
`{:ok, rows}`, one map per row with string keys, or `{:error, error}`.
`native_query!/2` returns the rows or raises:

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
#=> {:ok, [%{"__time" => "2016-06-27T00:00:00.000Z", "channel" => "#en.wikipedia", "edits" => 6650}, ...]}
```

An `Ecto.Druid.Interval` encodes to its ISO 8601 string, so you can also write
`intervals: [Ecto.Druid.Interval.last(day: 1)]`.

### Schemas as data sources

`dataSource` can be a schema module, which is replaced with its source name.
Before the query is sent, every column it reads (dimensions, filter columns,
aggregator fields and scan columns) is checked to be a field of the schema, a
virtual column or an output the query names, and an `ArgumentError` names any
that aren't. Druid expressions aren't parsed, so columns read only in an
expression aren't checked.

```elixir
MyApp.DruidRepo.native_query!(%{
  queryType: "topN",
  dataSource: MyApp.PageView,
  dimension: "page",
  ...
})
```

Pass `check_columns: false` to skip the check, such as for a column Druid has
that the schema doesn't map.

### Query context

A native query carries its context in the query map, so the repo's
`:context` config doesn't apply unless you pass `merge_context: true`. The
query's own context wins where the two overlap. Druid ignores context keys
it doesn't use, such as the SQL-only `sqlTimeZone`.

## Building the parts of a query

Filters, aggregators and expressions make up most of a native query. These
modules build them as plain maps, so they mix freely with ones you write by
hand:

  * `Ecto.Druid.Native.Filter`: `equals/3`, `range/2`, `in_/2`, `null/1`,
    `like/3`, `interval/2`, `expression/1`, `and_/1`, `or_/1` and `not_/1`,
    plus the legacy `selector/3` and `bound/2` for queries written for Druid
    before 27
  * `Ecto.Druid.Native.Aggregator`: `count/2`, the `long_`, `double_`,
    `float_` and `string_` aggregators, `filtered/2` and the sketches
  * `Ecto.Druid.Native.PostAggregator`: `arithmetic/4`, `expression/3`,
    `field_access/2` and `constant/2`
  * `Ecto.Druid.Native.Expression`: `expr/1`, which writes a Druid expression
    in Elixir syntax
  * `Ecto.Druid.Native.virtual_column/3` and `Ecto.Druid.Native.dimension/2`

```elixir
import Ecto.Druid.Native.{Aggregator, Expression, Filter}
alias Ecto.Druid.Native

%{
  queryType: "groupBy",
  dataSource: "wikipedia",
  intervals: [Ecto.Druid.Interval.new(~D[2016-06-27], day: 1)],
  granularity: "all",
  virtualColumns: [Native.virtual_column("net", expr(added - deleted), "LONG")],
  dimensions: ["page"],
  filter:
    and_([
      equals("channel", "#en.wikipedia"),
      range("added", lower: 10),
      null("user") |> not_(),
      if(robots_only?, do: equals("isRobot", "true"))
    ]),
  aggregations: [
    count("edits"),
    long_sum("net"),
    count("robot_edits") |> filtered(equals("isRobot", "true"))
  ]
}
```

`equals/3` and `range/2` work out the match value type from the value.
`and_/1` and `or_/1` leave out `nil` filters, so optional filters can be
written inline, as `robots_only?` is above.

In `expr/1`, variables are columns and `^` interpolates Elixir values, which
are quoted as literals, so a value can't break out of its place in the
expression:

```elixir
expr(if(deleted > 0, cast(added, "DOUBLE") / deleted, 0.0))
expr(user |> nvl(^default_user) |> lower() == ^user)
```

The builders cover the common parts of the spec. For anything else, write the
map yourself.

## Flattened results

Each query type nests its results differently, so `native_query/2` flattens
`timeseries`, `topN`, `groupBy`, `scan` and `windowOperator` results into one
map per row with `Ecto.Druid.Native.rows/3`. `"__time"` holds each row's time
bucket. This also names the values of `groupBy` results with the
`resultAsArray` context flag and of `scan` results in the `compactedList`
format. `windowOperator` results are bare arrays, so pass their column names
as `:columns`:

```elixir
MyApp.DruidRepo.native_query!(window_query, columns: ["channel", "rank"])
```

Other query types, such as `timeBoundary`, `segmentMetadata` and `search`,
come back as Druid sends them.

To skip flattening and get Druid's decoded response as is, pass `raw: true`:

```elixir
MyApp.DruidRepo.native_query!(query, raw: true)
#=> [%{"timestamp" => "2016-06-27T00:00:00.000Z",
#      "result" => [%{"channel" => "#en.wikipedia", "edits" => 6650}, ...]}]
```

`Ecto.Druid.Native.rows/3` flattens a raw response later, given the query that
produced it.

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

## Timeouts and canceling queries

Every native query gets a `queryId` in its context, unless it has one, and an
`Ecto.Adapters.Druid.NativeQueryError` carries it as `:query_id`. Druid stops
a query that runs past its own context `timeout`. When the request runs past
`:receive_timeout` (15 seconds by default) instead, the Broker would keep
running the query, so `native_query/2` cancels it and sets `:canceled` on the
error:

```elixir
case MyApp.DruidRepo.native_query(query, receive_timeout: 60_000) do
  {:ok, rows} -> rows
  {:error, %Ecto.Adapters.Druid.NativeQueryError{query_id: id, canceled: true}} -> ...
end
```

To cancel a query yourself, such as one running in another process, set its
`queryId` and pass it to `Druid.Client.Native.cancel/1`:

```elixir
Druid.Client.Native.cancel(query_id)
|> Druid.Client.request!(MyApp.DruidRepo.config())
```

`Druid.Client.Native.candidates/1` builds a request to list the segments a
native query would read, without running it.
