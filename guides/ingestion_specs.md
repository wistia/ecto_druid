# Ingestion Specs

Druid supervisor specs (Kafka ingestion) and batch ingestion tasks can live in
your project as EEx templates, with per-environment values from config. Mix
tasks render them and send them to Druid. Supervisors are kept in sync;
[batch tasks](#batch-ingestion-tasks) run once each time you submit them.

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

`Druid.Tasks.run/3` also takes a task spec as a map, and `Druid.Tasks.await/3`
waits for any task ID, including SQL-based ingestion queries submitted with
`Druid.Client.SQL.insert/3`. Submitting a batch ingestion task again ingests
its data again, adding to or replacing what's there depending on the spec's
`appendToExisting`.
