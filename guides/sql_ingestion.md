# SQL Ingestion

`Repo.insert_all/3` writes rows to Druid with
[SQL-based ingestion](https://druid.apache.org/docs/latest/multi-stage-query/).
It takes a list of rows or an `Ecto.Query`, like with any other Ecto adapter,
and runs Druid's `INSERT` or `REPLACE` statement as a task. It waits for the
task to finish, then returns `{rows_written, nil}`. `Repo.delete_all/2` deletes
rows the same way, and `Repo.update_all/3` changes them (see
[Deleting rows](#deleting-rows) and [Updating rows](#updating-rows)).

The cluster needs the `druid-multi-stage-query` extension loaded, and enough
free task slots for a controller and at least one worker.

## Inserting rows

Druid splits data into time chunks (segments), so every insert needs
`:partitioned_by`:

```elixir
MyApp.DruidRepo.insert_all(
  MyApp.PageViews,
  [
    %{time: ~U[2026-11-01 00:00:00Z], country: "US", views: 3},
    %{time: ~U[2026-11-01 01:00:00Z], country: "CA", views: 1}
  ],
  partitioned_by: :day,
  clustered_by: [:country]
)
#=> {2, nil}
```

The rows need a `__time` column, unless they're partitioned by `:all`. With a
schema, map a field to it with `source: :__time`.

Druid appends rows. It doesn't check them against what's already there, so
inserting the same rows twice stores them twice. Use `:overwrite` to
replace data instead.

## Inserting from a query

Pass a query to copy or transform data that's already in Druid, or to read
external data (see [Reading external data](#reading-external-data)). The
query's `select` names the new columns:

```elixir
query =
  from p in "page_views",
    where: time_in_interval(p.__time, "2026-11-01/P1D"),
    group_by: [time_floor(p.__time, "PT1H"), p.country],
    select: %{
      __time: time_floor(p.__time, "PT1H"),
      country: p.country,
      views: count()
    }

MyApp.DruidRepo.insert_all("page_views_hourly", query, partitioned_by: :day)
```

## Reading external data

`Ecto.Druid.Query.Table.extern/2` reads files, URLs or inline data, taking
Druid's [input source](https://druid.apache.org/docs/latest/ingestion/input-sources)
and [input format](https://druid.apache.org/docs/latest/ingestion/data-formats)
as maps, which it encodes as JSON (an already-encoded JSON string works too).
`extend/2` names the columns and their types:

```elixir
input = %{type: "s3", uris: ["s3://my-bucket/page_views.csv"]}
format = %{type: "csv", findColumnsFromHeader: true}

query =
  from e in extend(table(extern(^input, ^format)),
         ts: :string,
         country: :string,
         views: :long,
         tags: {:array, :string}
       ),
       select: %{__time: time_parse(e.ts), country: e.country, views: e.views, tags: e.tags}

MyApp.DruidRepo.insert_all("page_views", query, partitioned_by: :day)
```

The query reads from:

```sql
TABLE(EXTERN(?, ?)) EXTEND ("ts" VARCHAR, "country" VARCHAR, "views" BIGINT, "tags" VARCHAR ARRAY)
```

The column types are `:string`, `:long`, `:float`, `:double`, `:json` for
nested JSON, and `{:array, type}`. The columns are part of the SQL, so they
must be known at compile time, as a literal or a module attribute. To build
them at runtime, use `extern/3`, which takes them as a row signature: the
same keyword list, or Druid's list of `%{name: ..., type: ...}` maps:

```elixir
signature = [ts: :string, views: :long]
from e in table(extern(^input, ^format, ^signature)), select: ...
```

External data can only be read by SQL-based ingestion and queries from deep
storage: the Broker rejects it in a plain `Repo.all/2`.

Druid also has input-source-specific table functions, such as
`TABLE(s3(uris => ARRAY[...], format => 'csv')) EXTEND (...)`, but as of
Druid 38 they aren't registered outside Druid's own tests. A real cluster
rejects them with "Function s3 does not accept an EXTEND clause", so use
`extern/2`.

## Replacing data

`:overwrite` turns the insert into a `REPLACE`, which swaps out data rather
than adding to it. Pass `:all` to replace the whole data source, or an
interval to replace part of it:

```elixir
MyApp.DruidRepo.insert_all("page_views_hourly", query,
  partitioned_by: :day,
  overwrite: Ecto.Druid.Interval.new(~D[2026-11-01], ~D[2026-11-02])
)
```

Everything in the interval is dropped, including time chunks the new rows
don't cover. Rows outside the interval make the task fail. The interval
can be an `Ecto.Druid.Interval`, a `{start, stop}` tuple or an
`"start/stop"` string. Its bounds must be dates or date-times, not periods,
and line up with `:partitioned_by`: a `:day` partition can only replace whole
days.

## Options

  * `:partitioned_by` - Required. The time chunk size: `:all`, or one of
    `:second`, `:minute`, `:five_minute`, `:ten_minute`, `:fifteen_minute`,
    `:thirty_minute`, `:hour`, `:six_hour`, `:eight_hour`, `:day`, `:week`,
    `:month`, `:quarter` or `:year`. An ISO 8601 period such as `"PT6H"`
    also works.
  * `:clustered_by` - Columns to sort and split segments by within each time
    chunk. Put the columns you filter on most first.
  * `:overwrite` - `:all` or an interval to replace. See above.
  * `:context` - [Query context](https://druid.apache.org/docs/latest/multi-stage-query/reference#context-parameters)
    for the task, such as `%{maxNumTasks: 4}`. It's merged over the repo's
    `:context`.
  * `:timeout` - How long to wait for the task, in milliseconds. Defaults
    to `:infinity`.
  * `:poll_interval` - How often to check on the task, in milliseconds.
  * `:wait_for_segments` - When `true`, also wait until Historicals have
    loaded the new segments, so they can be queried as soon as
    `insert_all/3` returns. Defaults to `false`.

The task status and report requests go to the host in the repo's `:tasks`
config, as for `Druid.Tasks` (see [Ingestion Specs](ingestion_specs.md)).
With `:wait_for_segments`, the last check (that the Broker lists a new data
source) goes to the repo's own host.

`insert_all/3` raises `Druid.Tasks.Error` when the task fails or runs past
its `:timeout`, and `Druid.Client.RequestError` when Druid rejects the
statement. `:on_conflict`, `:conflict_target` and `:returning` aren't
supported.

## Deleting rows

Druid can't delete single rows in place, so `Repo.delete_all/2` rewrites the
time chunks in an `:interval` with every row the query doesn't match, using
`REPLACE`:

```elixir
MyApp.Repo.delete_all(
  from(e in MyApp.PageViews, where: e.country == "XX"),
  interval: Ecto.Druid.Interval.new(~D[2026-11-01], ~D[2026-11-08]),
  partitioned_by: :day
)
#=> {0, nil}
```

```sql
REPLACE INTO "page_views" OVERWRITE WHERE "__time" >= ? AND "__time" < ?
SELECT * FROM "page_views" AS p0
WHERE p0."__time" >= ? AND p0."__time" < ? AND ((p0."country" = 'XX')) IS NOT TRUE
PARTITIONED BY 'DAY'
```

Rows outside the interval are left alone, even if they match. Rows the
condition is `NULL` for, such as rows with no `country` above, are kept: the
condition is negated with `IS NOT TRUE`, not `NOT`, which would drop them.
Without a `where` clause, every row in the interval is deleted.

The query can only have `where` clauses on a data source: no joins, `select`
or `with_cte`. It takes the `insert_all/3` options above, except that
`:interval` replaces `:overwrite`:

  * `:interval` - Required. `:all`, to rewrite the whole data source, or an
    interval in the same forms as `:overwrite`. Its bounds must line up with
    `:partitioned_by`.
  * `:partitioned_by` - Required. Use the data source's segment granularity,
    or the rewritten time chunks will be partitioned differently from the
    rest.
  * `:clustered_by` - The data source's clustering columns, if it has any.
    Rewritten segments aren't clustered without it.

`delete_all/2` always returns `{0, nil}`, however many rows it deletes.
Druid's task doesn't report how many rows it dropped, and Ecto needs an
integer there, so don't read the `0` as "nothing matched". To know how many
rows a delete will remove, count them with a query first.

A delete rewrites every row in the interval, so keep the interval as small as
the data allows. To drop whole intervals, marking their segments unused with
`Druid.Client.DataSource.mark_unused/2` is cheaper, and
`Druid.Client.DataSource.kill/2` then removes them for good.

## Updating rows

`Repo.update_all/3` rewrites the time chunks in an `:interval` like
`delete_all/2`, but writes back every row, changing the columns of the rows
the query matches. A common use is backfilling a column that ingestion only
started collecting recently:

```elixir
MyApp.Repo.update_all(
  from(e in MyApp.Events, where: e.channel == "#cats"),
  [set: [category: "cats"]],
  interval: Ecto.Druid.Interval.new(~D[2026-01-01], ~D[2026-11-01]),
  partitioned_by: :day
)
#=> {0, nil}
```

```sql
REPLACE INTO "events" OVERWRITE WHERE "__time" >= ? AND "__time" < ?
SELECT e0."__time", e0."channel",
       CASE WHEN e0."__match" THEN CAST(? AS VARCHAR) ELSE e0."category" END AS "category",
       e0."count"
FROM (SELECT *, ((e0."channel" = ?)) IS TRUE AS "__match"
      FROM "events" AS e0 WHERE e0."__time" >= ? AND e0."__time" < ?) AS e0
PARTITIONED BY 'DAY'
```

Segments ingested before `category` existed read it as `NULL`, so rows the
query doesn't match keep a `NULL` category, and the rewritten segments get
the column. Druid still has to know the column from some segment, such as
newer data, or it rejects the statement with "Column 'category' not found".
The Broker picks up a new column a little while after the first segments
with it load, so a backfill run right after them may need to wait.

### The schema has to list every column

Druid can't select "every column but these", so `update_all/3` names every
column of the data source in its `SELECT`, and any column it leaves out is
dropped from the rewritten interval. It takes them from the query's schema,
which must use `Ecto.Druid.Schema`: its timestamp, dimensions and metrics
are the columns, and new values are cast to each column's type, so a value
of the wrong type can't change it. Fields defined with plain `field/3` aren't
columns, and can't be updated.

Keep the schema in step with what's been ingested: a column that only older
segments have, because it was dropped from the schema, is lost from any
interval `update_all/3` rewrites. A plain `Ecto.Schema` or a schemaless
query raises.

### Updates

  * `set` - Any expression: a value, another column, or Druid SQL functions,
    such as `set: [category: lookup(e.channel, "channel_categories")]`. A
    multi-value column takes a list (or an ARRAY expression), which replaces
    all of its values.
  * `inc` - Adds to a numeric column. A `NULL` column stays `NULL`.
  * `push` - Appends to an ARRAY or multi-value column. A `NULL` column
    becomes a one-element array. Druid keeps a multi-value column's values
    sorted (unless its `multiValueHandling` says otherwise), so the pushed
    value isn't necessarily last.
  * `pull` - Removes every occurrence of a value from a multi-value column.
    A column left empty becomes `NULL`. Druid has no function to remove
    elements from an ARRAY column, so `pull` raises for those.

`__time` can't be changed, since it decides which time chunk a row is in.
Rows the condition is `NULL` for aren't matched, and without a `where`
clause every row in the interval changes. On a rollup data source the
changed rows aren't re-aggregated with each other until compaction.

The query and options are as for `delete_all/2`: only `where` clauses,
`:interval` and `:partitioned_by` are required, and `:clustered_by` keeps the
data source's clustering. `update_all/3` also returns `{0, nil}`, since
Druid doesn't report how many rows it changed.

Druid can't change single rows, so `insert/2`, `update/2` and `delete/2`
raise.
