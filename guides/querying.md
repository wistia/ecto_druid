# Querying

Queries are written with `Ecto.Query` and sent to Druid's SQL API.

## Querying a data source

Query a data source by name, selecting the columns you need. Druid's time
column is `__time`:

```elixir
import Ecto.Query

MyApp.DruidRepo.all(
  from p in "page_views_hourly",
    where: p.country == ^country,
    group_by: p.browser,
    order_by: [desc: count()],
    limit: 10,
    select: %{browser: p.browser, views: count()}
)
```

Or describe the data source with a schema and query that. A schema built with
`Ecto.Druid.Schema` (see [Ingestion Specs](ingestion_specs.md)) maps `__time`
to a field and loads it as a `DateTime`. Use a plain `Ecto.Schema` with
`field :time, Ecto.Druid.DateTime, source: :__time` if you don't generate
ingestion specs.

## Druid SQL functions

`use Ecto.Druid.Query` imports macros for Druid's
[SQL functions](https://druid.apache.org/docs/latest/querying/sql-functions):
time bucketing, sketches, lookups, strings, arrays, JSON and more. Each
category is also its own module, such as `Ecto.Druid.Query.DateTime` or
`Ecto.Druid.Query.HLL`, if you'd rather import only what you use.

```elixir
import Ecto.Query
use Ecto.Druid.Query

MyApp.DruidRepo.all(
  from p in MyApp.PageViewsHourly,
    where: time_in_interval(p.time, {^~U[2026-11-01 00:00:00Z], ^~U[2026-11-08 00:00:00Z]}),
    group_by: [time_floor(p.time, "P1D"), p.country],
    select: %{
      day: time_floor(p.time, "P1D"),
      country: lookup(p.country, "countries", "Unknown"),
      views: sum(p.views),
      visitors: hll_sketch_estimate(ds_hll(p.unique_visitors))
    }
)
```

A schema field like `p.time` loads as a `DateTime`, but a computed value such
as `day` comes back as Druid returns it, an ISO 8601 string.

### Filtering on time

Filter on `__time` whenever you can. Druid uses the time filter to decide
which segments to read, so it's usually what makes a query fast.
`time_in_interval/2` takes either an ISO 8601 interval string such as
`"2026-11-01/P1W"` or a `{start, stop}` tuple of `DateTime`s,
`NaiveDateTime`s, `Date`s or strings, which is turned into an interval string.
Either way the start is inclusive and the stop is exclusive. Pinned
`DateTime`s also work in plain comparisons, such as `p.time >= ^since`.

`Ecto.Druid.Interval` builds intervals you can pin into `time_in_interval/2`
or put in a [native query's](native_queries.md) `intervals`. One bound can be
a period, given as a `Duration`, a keyword list or an ISO 8601 period string:

```elixir
interval = Ecto.Druid.Interval.new(~D[2026-11-01], week: 1)  # "2026-11-01/P1W"
interval = Ecto.Druid.Interval.last(day: 7)                  # the 7 days up to now

from p in MyApp.PageViewsHourly, where: time_in_interval(p.time, ^interval)
```

### Ecto's own expressions

Ecto's built-in query expressions become Druid SQL:

* `type(expr, type)` is a `CAST` to `BIGINT`, `DOUBLE`, `DECIMAL`, `BOOLEAN`,
  `VARCHAR`, `DATE` or `TIMESTAMP`. Druid has no map, binary or time type to
  cast to; use `parse_json/1` to make a JSON value.
* `datetime_add/3`, `date_add/3`, `ago/2` and `from_now/2` add a multiple of
  an `INTERVAL`, so the count can be fractional or an expression. Druid keeps
  timestamps to the millisecond, so adding microseconds rounds down to it.
* A JSON path such as `p.attributes["device"]["os"]` reads a scalar with
  `JSON_VALUE`, which returns a string, so it compares with strings. Use
  `json_query/2` for an object or array, or `json_value/3` with a `RETURNING`
  type. Druid can't address a key that contains a single quote.
* `value in p.tags`, for an `ARRAY` column, is `SCALAR_IN_ARRAY`.

### Sketches

Complex columns such as `unique_visitors` hold sketches. Merge them with the
matching aggregation (`ds_hll`, `ds_theta`, `ds_quantiles_sketch`, and so on)
and turn the result into a number with an estimate function. The sketch
functions' results load as Elixir values:

* Estimates with error bounds, from `hll_sketch_estimate_with_error_bounds`
  and `theta_sketch_estimate_with_error_bounds`, load as an
  `Ecto.Druid.Estimate` struct with `value`, `lower_bound` and `upper_bound`.
* `ds_get_quantiles`, `ds_histogram` and `ds_cdf` load as lists of floats.
* A sketch itself, selected from a column or built by an aggregation such as
  `ds_hll` or `tdigest_generate_sketch`, loads as its Base64 string.

```elixir
from p in MyApp.PageViewsHourly,
  select: %{
    visitors: hll_sketch_estimate_with_error_bounds(ds_hll(p.unique_visitors)),
    load_times: ds_histogram(ds_quantiles_sketch(p.load_times), [100, 500, 1000])
  }
#=> %{
#=>   visitors: %Ecto.Druid.Estimate{value: 1204.6, lower_bound: 1180.2, upper_bound: 1229.8},
#=>   load_times: [312.0, 840.0, 95.0, 12.0]
#=> }
```

To use a sketch you've loaded in another query, pin it and decode it with
`decode_base64_complex/2`:

```elixir
from p in MyApp.PageViewsHourly,
  select: theta_sketch_estimate(decode_base64_complex("thetaSketch", ^sessions))
```

## Joins, subqueries and table functions

Joins, subqueries, `union`/`union_all`, and window functions (via
`Ecto.Query.WindowAPI`) all work. Druid lookups are tables in the `lookup`
schema with `k` and `v` columns, so you can join one as well as calling
`lookup/3`. An `Ecto.Druid.Lookup` schema makes this easier (see
[Lookups](lookups.md)):

```elixir
# Join a lookup
from p in MyApp.PageViewsHourly,
  join: c in MyApp.Countries, on: c.code == p.country,
  group_by: c.name,
  select: {c.name, sum(p.views)}

# Filter on a subquery
top = from p in MyApp.PageViewsHourly,
  group_by: p.country, order_by: [desc: sum(p.views)], limit: 5, select: p.country

from p in MyApp.PageViewsHourly,
  where: p.country in subquery(top),
  group_by: p.country,
  select: {p.country, sum(p.views)}

# Expand an ARRAY or multi-value column into rows
from p in MyApp.PageViewsHourly,
  cross_join: t in unnest(p.tags, :tag),
  group_by: t.tag,
  select: {t.tag, sum(p.views)}
```

## Query context

Druid's [query context](https://druid.apache.org/docs/latest/querying/sql-query-context)
(timeouts, time zone, approximation settings, and so on) can be set for the
whole repo with the `:context` config (see [Getting Started](getting_started.md)),
or per call:

```elixir
MyApp.DruidRepo.all(query, context: %{sqlTimeZone: "America/New_York", timeout: 30_000})
```

Per-call values override the repo config.

## Timeouts and canceling queries

`:receive_timeout` sets how long a call waits for Druid's response, in
milliseconds (15 seconds by default). When it runs out, the Broker would
keep running the query, so the adapter cancels it by its `sqlQueryId` and
then raises the `Req.TransportError`:

```elixir
MyApp.DruidRepo.all(query, receive_timeout: 60_000)
```

Every query gets a `sqlQueryId` in its context unless it has one. To cancel
a query yourself, such as one running in another process, set its
`sqlQueryId` and pass it to `Druid.Client.SQL.cancel/1`. Druid's own
`timeout` context parameter limits how long the query may run in Druid,
whether or not anyone is still waiting for it.

## Querying from deep storage

The Broker only reads segments that are loaded on Historicals. Retention
rules with zero replicas keep older segments in deep storage only, which
is cheaper but leaves them invisible to normal queries. Pass
`deep_storage: true` to read them anyway through Druid's
[query from deep storage API](https://druid.apache.org/docs/latest/querying/query-deep-storage):

```elixir
MyApp.DruidRepo.all(query, deep_storage: true)
```

The query runs as an asynchronous task. The adapter submits it, checks its
status until it finishes, then reads the results. Even a small query takes
several seconds, so only use this for data that isn't loaded. Pass a
keyword list in place of `true` to change how long it waits:

* `:timeout` - How long to wait for the query to finish, in milliseconds or
  `:infinity`. Defaults to five minutes. When it runs out, the query is
  canceled in Druid and `Ecto.Adapters.Druid.StatementError` is raised.
* `:poll_interval` - How often to check the query's status, in
  milliseconds. Defaults to `1_000`.

```elixir
MyApp.DruidRepo.all(query, deep_storage: [timeout: :timer.minutes(30)])
```

A query that Druid rejects up front raises `Druid.Client.RequestError`, like
any other query. One that fails while running raises
`Ecto.Adapters.Druid.StatementError`, with Druid's error in `:details`.

Setting `deep_storage:` in the repo config sends every query from that repo
through deep storage. That's useful for a separate repo that only reads cold
data. A per-call value, including `deep_storage: false`, overrides it.

`Repo.stream/2` fetches the results one page at a time, so large results
don't have to fit in memory at once:

```elixir
query
|> MyApp.DruidRepo.stream(deep_storage: true)
|> Stream.each(&write_row/1)
|> Stream.run()
```

The query only starts when the stream is first enumerated. Without
`deep_storage`, `Repo.stream/2` still works, but the Broker sends every row
in one response.

### What deep storage queries need from the cluster

* The Broker plans the query from the data source's schema, which it learns
  from loaded segments. A data source with no loaded segments at all is
  reported as not found, unless the cluster sets
  `druid.centralizedDatasourceSchema.enabled=true`. A common setup loads recent data and keeps the rest in deep
  storage only:

  ```elixir
  [
    %{"type" => "loadByPeriod", "period" => "P30D", "tieredReplicants" => %{"_default_tier" => 2}},
    %{"type" => "loadForever", "tieredReplicants" => %{}, "useDefaultTierForNull" => false}
  ]
  ```

* By default Druid keeps the results in the query's task report, which
  limits how many rows it can return. For large results, configure
  [durable storage](https://druid.apache.org/docs/latest/operations/durable-storage)
  on the cluster and send `selectDestination: "durableStorage"` in the
  context. `rowsPerPage` then controls the page size that `Repo.stream/2`
  reads:

  ```elixir
  MyApp.DruidRepo.stream(query,
    deep_storage: true,
    context: %{selectDestination: "durableStorage", rowsPerPage: 50_000}
  )
  ```

* Rows still being ingested are skipped unless you add
  `includeSegmentSource: "realtime"` to the context.

`Druid.Client.SQL.Statement` builds the underlying requests if you want to
submit a query and collect its results later yourself.

## Inspecting and hand-writing SQL

`to_sql/1` returns the SQL and parameters a query will send:

```elixir
MyApp.DruidRepo.to_sql(from p in "page_views_hourly", select: count())
#=> {"SELECT count(*) FROM \"page_views_hourly\" AS p0", []}
```

To run SQL you've written yourself, send it with `Druid.Client.SQL`. Rows come
back as lists, and parameters take a Druid SQL type:

```elixir
Druid.Client.SQL.query(
  "SELECT channel, COUNT(*) FROM wikipedia GROUP BY 1 ORDER BY 2 DESC LIMIT ?",
  [%{type: "BIGINT", value: 10}]
)
|> Druid.Client.request!(MyApp.DruidRepo.config())
```
