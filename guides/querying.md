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
`field :time, Ecto.Druid.Timestamp, source: :__time` if you don't generate
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

# Read several data sources as one, matching columns by name
from p in table(append(["page_views_hourly", "page_views_backfill"])),
  group_by: p.country,
  select: {p.country, sum(p.views)}
```

## Subtotals

`rollup/1`, `cube/1` and `grouping_sets/1` (in `group_by`) compute several
levels of aggregation in one query. In subtotal rows the rolled-up columns
are `NULL`; `grouping/1` tells them apart from real `NULL`s, with a bit set
for each argument the row's set leaves out:

```elixir
# Views per country and device, per country, and in total
from p in MyApp.PageViewsHourly,
  group_by: rollup([p.country, p.device]),
  select: %{
    country: p.country,
    device: p.device,
    views: sum(p.views),
    level: grouping([p.country, p.device])
  }
#=> [%{country: "US", device: "mobile", views: 812, level: 0},
#=>  %{country: "US", device: nil, views: 1290, level: 1},
#=>  ...
#=>  %{country: nil, device: nil, views: 5403, level: 3}]
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

## Time zones

Druid stores `__time` in UTC. To bucket and filter by days that start
somewhere else, such as a fixed UTC-5 day that ignores daylight saving time,
set the `sqlTimeZone` context parameter, for the repo or per call:

```elixir
config :my_app, MyApp.DruidRepo, context: %{sqlTimeZone: "-05:00"}
```

With it set:

* Time functions such as `time_floor/2`, `date_trunc/2`, `floor/2`,
  `time_extract/2` and `time_format/2` work in that zone.
* `Date` and `NaiveDateTime` parameters, and interval strings without an
  offset (including `time_in_interval/2` with `Date` bounds), are times in
  that zone. `~D[2026-11-01]` is midnight UTC-5, `2026-11-01T05:00:00Z`.
* `DateTime` parameters are the instant they name. Druid ignores the offset
  of a timestamp parameter, so the adapter sends the wall-clock time in
  `sqlTimeZone`.
* `:date` and `:naive_datetime` results are the date and wall-clock time in
  that zone. `:utc_datetime`, `Ecto.Druid.Timestamp` and `Ecto.Druid.DateTime`
  results are in UTC.

```elixir
from(p in "page_views",
  where: p.__time >= ^~D[2026-11-01] and p.__time < ^~D[2026-11-08],
  group_by: time_floor(p.__time, "P1D"),
  select: %{day: type(time_floor(p.__time, "P1D"), :date), views: sum(p.views)}
)
|> MyApp.DruidRepo.all(context: %{sqlTimeZone: "-05:00"})
#=> [%{day: ~D[2026-11-01], views: 1204}, %{day: ~D[2026-11-02], views: 1311}, ...]
```

To use a zone in one place without changing the session's, pass it to the
function. The result is still a UTC timestamp:

```elixir
select: type(time_floor(p.__time, "P1D", nil, "-05:00"), :utc_datetime)
#=> ~U[2026-11-01 05:00:00Z]
```

### Choosing a zone

* `"-05:00"`, `"EST"` and `"Etc/GMT+5"` are all UTC-5 the whole year
  (`Etc/GMT` zones have their sign inverted). `"America/New_York"` follows
  daylight saving time, so its days start at 04:00 UTC in the summer.
* Druid treats a zone it doesn't recognize, such as `"UTC-5"`, as UTC
  without an error.
* Sending `DateTime` parameters with a zone that has daylight saving time
  needs a time zone database, such as `:tz` or `:tzdata`, set with
  `config :elixir, :time_zone_database, ...`. Fixed offsets don't. When
  clocks go back, Druid reads a time in the repeated hour as the first one.

### Data rolled up to days in a zone

A data source ingested with a period granularity in a zone, such as
`query_granularity: %{"type" => "period", "period" => "P1D", "timeZone" => "-05:00"}`
in `Ecto.Druid.Schema.Spec.data_schema/2`, stores each day's rows at the
start of that day, 05:00 UTC for UTC-5. Queries with the same
`sqlTimeZone` line up with those days: `Date` filters land on day
boundaries, and `time_floor(p.__time, "P1D")` gives back each row's day.

[Native queries](native_queries.md) don't use `sqlTimeZone`. Give them a
period granularity with a `timeZone`, such as
`%{type: "period", period: "P1D", timeZone: "-05:00"}`. Their `intervals`
are in UTC unless a bound has an offset, so use `DateTime` bounds or strings
like `"2026-11-01T00:00:00-05:00/2026-11-08T00:00:00-05:00"`.

[SQL ingestion](sql_ingestion.md) only partitions by UTC periods. Druid
rejects a time zone in `PARTITIONED BY`, and with `sqlTimeZone` set it
checks `:overwrite` and `:interval` bounds against UTC partitions.

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

## Streaming results

`Repo.stream/2` reads the Broker's response as it arrives, so a large
result doesn't have to fit in memory. It asks Druid for one row per line
(the `arrayLines` result format) and decodes each row as the stream takes
it, reading only a little ahead of what has been taken:

```elixir
query
|> MyApp.DruidRepo.stream(receive_timeout: 60_000)
|> Stream.each(&write_row/1)
|> Stream.run()
```

The query only starts when the stream is first enumerated. `:receive_timeout`
applies to each part of the response, not the whole of it, so a long result
can take longer than the timeout to read, as long as Druid keeps sending it.

The Broker sends a 200 before it has every row, so a query that fails
partway can't change the status. Druid ends a complete response with a
blank line, and when that's missing the stream raises rather than return
part of the result. A stream that is halted early, such as with
`Enum.take/2`, or that fails, cancels its query in case the Broker is still
running it.

Query errors that Druid reports up front raise `Druid.Client.RequestError`,
with Druid's `errorCode` in `:error_code` and its `category` in `:category`:

```elixir
try do
  MyApp.DruidRepo.all(query)
rescue
  error in Druid.Client.RequestError ->
    if error.category == "CAPACITY_EXCEEDED", do: retry_later(), else: reraise(error, __STACKTRACE__)
end
```

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
Druid keeps running a statement that nobody is waiting on, so one that runs
past its timeout, or whose status can't be checked because the requests keep
failing, is canceled before the error is raised.

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

The query only starts when the stream is first enumerated.

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
