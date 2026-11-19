# Ingestion Specs

Druid supervisor specs (Kafka ingestion) and batch ingestion tasks can live in
your project as EEx templates, with per-environment values from config. Mix
tasks render them and send them to Druid. Supervisors are kept in sync;
[batch tasks](#batch-ingestion-tasks) run once each time you submit them, or
once per day over a range for [backfills](#backfills).

## Templates

Put one supervisor spec per file in `priv/druid/supervisors/*.json.eex`. Each
file is the JSON you'd submit to Druid, with EEx for the values that change
between environments:

```eex
{
  "type": "kafka",
  "spec": {
    "ioConfig": {
      "topic": "page_views",
      "consumerProperties": <%= json @kafka_consumer_properties %>,
      "taskCount": <%= @task_count %>
    },
    "dataSchema": <%= data_schema MyApp.PageViewsHourly, segment_granularity: "DAY" %>
  }
}
```

See `Druid.Supervisors.Template.Helpers` for the helpers available in
templates.

## Generating the data schema

`data_schema` generates the timestamp, dimensions and metrics from an Ecto
schema that describes how each column is ingested (see `Ecto.Druid.Schema`):

```elixir
defmodule MyApp.PageViewsHourly do
  use Ecto.Druid.Schema

  @primary_key false
  schema "page_views_hourly" do
    timestamp :time, column: "ts", format: "millis"
    dimension :country, :string
    dimension :visitor_key, :string, from: "user_key"
    metric :views, :integer, aggregate: :count
    metric :watch_time, :float, aggregate: :sum, from: "watch_seconds"
    metric :unique_visitors, Ecto.Druid.HLLSketch, from: "visitor_id", lg_k: 12
  end
end
```

`from:` reads an input field with a different name. Metrics support it
directly; for dimensions it generates a `transformSpec` transform, because
Druid dimensions can only read the input field of their own name.

The same schema is used for [queries](querying.md). Add
`import_deps: [:ecto_druid]` to your `.formatter.exs` to write the schema
macros without parentheses.

## Configuring values

Supply the template's values (`@kafka_consumer_properties`, `@task_count`) from
your Druid repo's config, for example from environment variables in
`config/runtime.exs`:

```elixir
config :my_app, MyApp.DruidRepo,
  supervisors: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{
      kafka_consumer_properties: %{"bootstrap.servers" => System.get_env("KAFKA_BROKERS")},
      task_count: 1
    },
    specs: %{"page_views_hourly" => %{task_count: 4}}
  ]
```

`assigns` apply to every template. `specs` adds assigns for one spec, keyed by
its template path without the extension.

## Rendering and syncing

Render or submit the specs:

```sh
mix druid.supervisors.render
mix druid.supervisors.sync --dry-run
mix druid.supervisors.sync
```

In a release, call `Druid.Supervisors.sync(MyApp.DruidRepo)` instead. Druid
only restarts a supervisor when its spec changed. See `Druid.Supervisors` for
partials and all options.

[Compaction configs](compaction.md), [retention rules](retention.md) and
[lookups](lookups.md) are managed the same way.

## Testing streaming ingestion

A test that checks what a supervisor spec makes of real messages has to
wait on Druid twice: before writing to the stream, and before reading what
was stored. `Druid.Supervisors` has a function for each:

```elixir
test "page views are rolled up by country" do
  [{status, _}] = Druid.Supervisors.sync(MyApp.DruidRepo, only: ["page_views_hourly"])
  assert status in [:created, :updated, :unchanged]

  # A spec with "useEarliestOffset": false starts from the end of the topic,
  # so anything written before its tasks are reading is never ingested.
  {:ok, _} =
    Druid.Supervisors.await_running(MyApp.DruidRepo, "page_views_hourly", timeout: 120_000)

  produce_page_views()

  # The rows can be queried as soon as the tasks have read them, while
  # the tasks still hold them in memory.
  # ...

  # Publish the segments now instead of at the end of the taskDuration,
  # and wait until Historicals serve them.
  {:ok, _} =
    Druid.Supervisors.handoff(MyApp.DruidRepo, "page_views_hourly",
      wait_for_segments: true,
      timeout: 300_000
    )

  # The rows now come from the published segments, which is what
  # compaction and retention rules act on.
  # ...
end
```

`await_running/3` returns an error rather than waiting out its timeout when
the supervisor is suspended or Druid reports it unhealthy, with the
supervisor's recent errors in the message. `handoff/3` returns the status of
each task it stopped. If queries use lookups, wait for those to load too
(see [Lookups](lookups.md#waiting-for-lookups-to-load)).

## Batch ingestion tasks

Batch tasks such as `index_parallel` go in `priv/druid/tasks/*.json.eex`.
They use the same template format and helpers as supervisor specs:

```eex
{
  "type": "index_parallel",
  "spec": {
    "ioConfig": {
      "type": "index_parallel",
      "inputSource": {"type": "s3", "prefixes": [<%= json @source_prefix %>]},
      "inputFormat": {"type": "json"}
    },
    "tuningConfig": {"type": "index_parallel", "partitionsSpec": {"type": "dynamic"}},
    "dataSchema": <%= data_schema MyApp.PageViewsHourly,
                        segment_granularity: "DAY",
                        intervals: [@interval] %>
  }
}
```

Configure their values under `:tasks`:

```elixir
config :my_app, MyApp.DruidRepo,
  tasks: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{source_prefix: System.get_env("PAGE_VIEWS_PREFIX")}
  ]
```

A task runs once each time you submit it, so values that change from run to
run, such as the interval to reindex, are passed when running it. They are
merged over the configured assigns:

```sh
mix druid.tasks.render --only reindex_page_views --assign interval=2026-11-01/P1D
mix druid.tasks.run reindex_page_views --assign interval=2026-11-01/P1D --wait-for-segments
```

`mix druid.tasks.run` submits the task and waits for it to finish.
`--wait-for-segments` also waits until Historicals have loaded the new
segments, so the data can be queried as soon as it returns. Pass `--no-wait`
to submit and exit.

In a release, or from your own code, use `Druid.Tasks`:

```elixir
{:ok, %{"status" => "SUCCESS"}} =
  Druid.Tasks.run(MyApp.DruidRepo, "reindex_page_views",
    assigns: %{interval: "2026-11-01/P1D"},
    wait_for_segments: true
  )
```

### Backfills

To reprocess a range of time, run a backfill template once per day (or
`hour`, `week`, `month`) with `mix druid.tasks.backfill`. Backfill templates
go in their own directory, `priv/druid/backfills`. Each task is rendered with
`@interval`, `@start` and `@stop` for its part of the range:

```eex
{
  "type": "index_parallel",
  "spec": {
    "ioConfig": {
      "type": "index_parallel",
      "inputSource": {
        "type": "s3",
        "prefixes": <%= partition_prefixes "s3://#{@bucket}/page_views", @interval,
                          "year=%Y/month=%m/day=%d/" %>
      },
      "inputFormat": {"type": "parquet"},
      "appendToExisting": false
    },
    "tuningConfig": {"type": "index_parallel", "maxNumConcurrentSubTasks": <%= @subtasks %>},
    "dataSchema": <%= data_schema MyApp.PageViewsHourly,
                        segment_granularity: "DAY",
                        intervals: [@interval] %>
  }
}
```

`partition_prefixes` lists the time-partitioned input paths the interval
covers. `intervals: [@interval]` makes each task replace exactly its interval
and skip input rows outside it.

Backfills use the `:tasks` config. Set anything that differs under
`:backfills`, whose assigns are merged over the `:tasks` ones:

```elixir
config :my_app, MyApp.DruidRepo,
  tasks: [port: 8888, assigns: %{bucket: "my-bucket"}],
  backfills: [assigns: %{subtasks: 8}]
```

Check what will run, then run it:

```sh
mix druid.tasks.backfill page_views --from 2026-10-01 --to 2026-11-01 --dry-run --out tmp/backfill
mix druid.tasks.backfill page_views --from 2026-10-01 --to 2026-11-01 --concurrency 4
```

`--to` is exclusive. `--concurrency` caps how many of the backfill's tasks run
at once, so it doesn't take every worker slot from streaming ingestion; the
next task is submitted as each one finishes. Progress prints as tasks finish,
and failed days are listed at the end, so you can rerun just those.

The submitted task IDs are recorded in `tmp/druid/backfills/` (or
`--tasks-file`). If you stop waiting, or pass `--no-wait`, check on them
later:

```sh
mix druid.tasks.status tmp/druid/backfills/page_views-20261115T120000Z.jsonl
mix druid.tasks.status tmp/druid/backfills/page_views-20261115T120000Z.jsonl --wait
```

Status checks that fail with a transient error, such as a 503 from an
Overlord that is changing leaders, are retried for a few seconds. If they
keep failing, the backfill stops waiting and reports the tasks it was
checking as failed with the request's error, but those tasks may still be
running in Druid. Check them with `mix druid.tasks.status` before rerunning
those days, or the rerun submits them a second time.

Days start at midnight UTC. For days in another zone, pass
`--time-zone America/New_York`, which needs a time zone database such as
`:tz` or `:tzdata` configured in your app.

Druid replaces whole segments, so:

* Make sure each task's input holds all of the interval's data, not just the
  part being fixed, for example when several pipelines write to one data
  source.
* Don't use a step shorter than the segment granularity. Druid widens a
  task's intervals to whole segments, so 6-hour tasks on `DAY` segments would
  each replace the whole day.

From code or a release, use `Druid.Tasks.backfill/5`, which takes the same
options and returns a `Druid.Tasks.Run` per interval.

`Druid.Tasks.run/3` also takes a task spec as a map, and `Druid.Tasks.await/3`
waits for any task ID, including SQL-based ingestion queries submitted with
`Druid.Client.SQL.insert/3`. Submitting a batch ingestion task again ingests
its data again, adding to or replacing what's there depending on the spec's
`appendToExisting`.
