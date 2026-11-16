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
run, such as the interval to backfill, are passed when running it. They are
merged over the configured assigns:

```sh
mix druid.tasks.render backfill_page_views --assign interval=2026-11-01/P1D
mix druid.tasks.run backfill_page_views --assign interval=2026-11-01/P1D --wait-for-segments
```

`mix druid.tasks.run` submits the task and waits for it to finish.
`--wait-for-segments` also waits until Historicals have loaded the new
segments, so the data can be queried as soon as it returns. Pass `--no-wait`
to submit and exit.

In a release, or from your own code, use `Druid.Tasks`:

```elixir
{:ok, %{"status" => "SUCCESS"}} =
  Druid.Tasks.run(MyApp.DruidRepo, "backfill_page_views",
    assigns: %{interval: "2026-11-01/P1D"},
    wait_for_segments: true
  )
```

### Backfills

To reprocess a range of time, run a template once per day (or `hour`, `week`,
`month`) with `mix druid.tasks.backfill`. Each task is rendered with
`@interval`, `@start` and `@stop` for its part of the range:

```eex
{
  "type": "index_parallel",
  "spec": {
    "ioConfig": {
      "type": "index_parallel",
      "inputSource": {
        "type": "s3",
        "prefixes": <%= partition_prefixes "s3://my-bucket/page_views", @interval,
                          "year=%Y/month=%m/day=%d/" %>
      },
      "inputFormat": {"type": "parquet"},
      "appendToExisting": false
    },
    "tuningConfig": {"type": "index_parallel", "maxNumConcurrentSubTasks": 8},
    "dataSchema": <%= data_schema MyApp.PageViewsHourly,
                        segment_granularity: "DAY",
                        intervals: [@interval] %>
  }
}
```

`partition_prefixes` lists the time-partitioned input paths the interval
covers. `intervals: [@interval]` makes each task replace exactly its interval
and skip input rows outside it.

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
