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

### Sketches

Complex columns such as `unique_visitors` hold sketches. Merge them with the
matching aggregation (`ds_hll`, `ds_theta`, `ds_quantiles_sketch`, and so on)
and turn the result into a number with an estimate function. A sketch selected
as is loads as its Base64 string.

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
