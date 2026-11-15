# Ecto.Adapters.Druid

Ecto Druid [(documentation)](https://hexdocs.pm/ecto_druid) allows interacting with Druid via Ecto. It features:

* An Ecto adapter for Druid
* Modules that provide Druid's SQL functions (see `Ecto.Druid.Query`)
* Types for Druid's complex types
* Schemas for Druid's system tables (`sys.*` and `INFORMATION_SCHEMA.*`)
* A Druid API client
* Supervisor specs (Kafka ingestion), compaction configs, retention rules and
  lookups managed as EEx templates, with per-environment values from config
  (see `Druid.Supervisors`, `Druid.Compaction`, `Druid.Retention` and
  `Druid.Lookups`)

The library targets and is tested against Apache Druid 38.0.0.

To learn more about getting started, see the [Ecto repository](https://github.com/elixir-ecto/ecto).

## Supervisor specs

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

The same schema is used for queries. Add `import_deps: [:ecto_druid]` to your
`.formatter.exs` to write the schema macros without parentheses.

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

Then render or submit them:

```sh
mix druid.supervisors.render
mix druid.supervisors.sync --dry-run
mix druid.supervisors.sync
```

In a release, call `Druid.Supervisors.sync(MyApp.DruidRepo)` instead. Druid only
restarts a supervisor when its spec changed. See `Druid.Supervisors` for
partials and all options.

## Compaction, retention rules and lookups

Compaction configs, retention rules and lookups work the same way, each from
its own directory and config key.

`priv/druid/compaction/page_views_hourly.json.eex` holds the automatic
compaction config for the `page_views_hourly` data source. The schema helpers
work here too:

```eex
{
  "skipOffsetFromLatest": "P1D",
  "dimensionsSpec": <%= dimensions_spec MyApp.PageViewsHourly %>,
  "metricsSpec": <%= metrics_spec MyApp.PageViewsHourly, combining: true %>,
  "tuningConfig": {"maxNumConcurrentSubTasks": <%= @max_subtasks %>}
}
```

This uses Druid's compaction API, which works whether the cluster runs
compaction as supervisors (the default) or on the Coordinator.

`priv/druid/retention/page_views_hourly.json.eex` holds the rules for the
`page_views_hourly` data source:

```eex
[
  {"type": "loadByPeriod", "period": "P2Y",
   "tieredReplicants": {<%= json @historical_tier %>: <%= @replicas %>}},
  {"type": "dropForever"}
]
```

`priv/druid/lookups/countries.json.eex` defines the `countries` lookup. A
template renders only the lookup's `lookupExtractorFactory`. The library
manages the version and only bumps it when the lookup changes:

```eex
{"type": "map", "map": <%= json @countries %>}
```

```elixir
config :my_app, MyApp.DruidRepo,
  compaction: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{max_subtasks: 1}
  ],
  retention: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{historical_tier: "_default_tier", replicas: 2}
  ],
  lookups: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{countries: %{"US" => "United States"}}
  ]
```

```sh
mix druid.compaction.sync --dry-run
mix druid.compaction.sync
mix druid.retention.sync --dry-run
mix druid.retention.sync
mix druid.lookups.sync --dry-run
mix druid.lookups.sync
```

Each only submits what changed. Retention sync also refuses rules that name a
tier with no Historicals, since Druid would accept them and unload the data.
See `Druid.Compaction`, `Druid.Retention` and `Druid.Lookups` for details.

## System tables

Druid's metadata tables have ready-made schemas: `Ecto.Druid.Sys.Segments`,
`ServerSegments`, `Servers`, `ServerProperties`, `Tasks` and `Supervisors` for
the `sys` schema, and `Ecto.Druid.InformationSchema.Schemata`, `Tables`,
`Columns` and `Routines` for `INFORMATION_SCHEMA`. Query them like any other
schema:

```elixir
import Ecto.Query

MyApp.DruidRepo.all(
  from s in Ecto.Druid.Sys.Segments,
    where: s.datasource == "page_views_hourly" and s.is_active == 1,
    select: %{segment_id: s.segment_id, size: s.size, num_rows: s.num_rows}
)

MyApp.DruidRepo.all(
  from c in Ecto.Druid.InformationSchema.Columns,
    where: c.table_schema == "druid" and c.table_name == "page_views_hourly",
    order_by: c.ordinal_position,
    select: {c.column_name, c.data_type}
)
```

Flags such as `is_active` are 0/1 integers, as Druid types them. Columns
holding JSON (a segment's `shard_spec`, a supervisor's `spec`) load as maps
(see `Ecto.Druid.JSON`).

## Druid API client

`Druid.Client` sends requests to Druid's HTTP API. Each module under it builds
`Req` requests for one part of the API, which you then send with
`Druid.Client.request/2` or `Druid.Client.request!/2`:

```elixir
druid = [host: "localhost", port: 8888]

Druid.Client.Task.all(state: "running") |> Druid.Client.request!(druid)
Druid.Client.DataSource.mark_unused("wikipedia", %{"interval" => "2015-09-12/2015-09-13"})
|> Druid.Client.request!(druid)
```

| Module | API |
| --- | --- |
| `Druid.Client.SQL` | SQL queries, SQL-based ingestion, and query cancellation |
| `Druid.Client.SQL.Statement` | Asynchronous queries from deep storage |
| `Druid.Client.Native` | Native JSON queries |
| `Druid.Client.Task` | Submitting, listing, inspecting, and shutting down tasks |
| `Druid.Client.Supervisor` | Streaming ingestion and compaction supervisors |
| `Druid.Client.DataSource` | Data sources and their segments, including marking segments used or unused and kill tasks |
| `Druid.Client.Metadata` | Segments in the metadata store and segment loading |
| `Druid.Client.Compaction` | Automatic compaction configs and status |
| `Druid.Client.Retention` | Retention rules |
| `Druid.Client.Lookup` | Lookups |
| `Druid.Client.Config` | Coordinator, Broker, and Overlord worker dynamic config |
| `Druid.Client.Status` | Service health, leaders, readiness, and workers |

## Upgrading from 0.5.x

The SQL function macros moved from `Ecto.Druid.Query` into per-category
submodules (`Ecto.Druid.Query.Numeric`, `Ecto.Druid.Query.DateTime`, and so
on). Replace `import Ecto.Druid.Query` with `use Ecto.Druid.Query` to bring
them all in (this also handles the `import Kernel, except: [...]` clause for
you), or import the individual submodules you need.

## Running Tests

```sh
git clone https://github.com/wistia/ecto_druid.git
cd ecto_druid

# Start druid
docker compose up -d druid

# Wait for druid to start up, then load data into it
curl "http://localhost:9888/druid/indexer/v1/task" \
  --header 'Content-Type: application/json' \
  -d @ingestion_spec.json

# Once the data has loaded
mix test
```

The compose file maps services to non-default host ports so they don't clash
with other local containers: Druid router on 9888, Druid broker on 9082,
Postgres on 6432, ZooKeeper on 3181, and SeaweedFS (S3 API) on 9900.
