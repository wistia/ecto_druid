# Compaction, Retention and Lookups

Compaction configs, retention rules and lookups work the same way as
[ingestion specs](ingestion_specs.md): EEx templates in your project, values
from config, and Mix tasks that sync them. Each has its own directory and
config key.

## Compaction

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
compaction as supervisors (the default) or on the Coordinator. See
`Druid.Compaction`.

## Retention rules

`priv/druid/retention/page_views_hourly.json.eex` holds the rules for the
`page_views_hourly` data source:

```eex
[
  {"type": "loadByPeriod", "period": "P2Y",
   "tieredReplicants": {<%= json @historical_tier %>: <%= @replicas %>}},
  {"type": "dropForever"}
]
```

Retention sync refuses rules that name a tier with no Historicals, since Druid
would accept them and unload the data. See `Druid.Retention`.

## Lookups

`priv/druid/lookups/countries.json.eex` defines the `countries` lookup. A
template renders only the lookup's `lookupExtractorFactory`. The library
manages the version and only bumps it when the lookup changes:

```eex
{"type": "map", "map": <%= json @countries %>}
```

See `Druid.Lookups`.

## Configuration

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

## Syncing

```sh
mix druid.compaction.sync --dry-run
mix druid.compaction.sync
mix druid.retention.sync --dry-run
mix druid.retention.sync
mix druid.lookups.sync --dry-run
mix druid.lookups.sync
```

Each only submits what changed.
