# SQL Ingestion

`Repo.insert_all/3` writes rows to Druid with
[SQL-based ingestion](https://druid.apache.org/docs/latest/multi-stage-query/).
It takes a list of rows or an `Ecto.Query`, like with any other Ecto adapter,
and runs Druid's `INSERT` or `REPLACE` statement as a task. It waits for the
task to finish, then returns `{rows_written, nil}`.

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
external data with `Ecto.Druid.Query.Table.extern/3`. The query's `select`
names the new columns:

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

## Updating and deleting

Druid can't update or delete individual rows, so `insert/2`, `update/2`,
`delete/2`, `update_all/3` and `delete_all/2` raise. To change data, replace
its interval with `:overwrite`. To drop it, mark its segments unused with
`Druid.Client.DataSource.mark_unused/2`, then remove them for good with
`Druid.Client.DataSource.kill/2`.
