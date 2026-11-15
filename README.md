# Ecto.Adapters.Druid

Ecto Druid [(documentation)](https://hexdocs.pm/ecto_druid) allows interacting with Druid via Ecto. It features:

* An Ecto adapter for Druid
* Modules that provide Druid's SQL functions (see `Ecto.Druid.Query`)
* Types for Druid's complex types
* A Druid API client
* Supervisor specs (Kafka ingestion, automatic compaction) managed as EEx
  templates, with per-environment values from config (see `Druid.Supervisors`)

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
partials, compaction supervisors, and all options.

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
Postgres on 6432, ZooKeeper on 3181, and MinIO on 9900/9901.
