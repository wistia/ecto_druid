# Compaction

Automatic compaction configs work the same way as
[ingestion specs](ingestion_specs.md): EEx templates in your project, values
from config, and Mix tasks that sync them.

## Templates

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

## Configuration

```elixir
config :my_app, MyApp.DruidRepo,
  compaction: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{max_subtasks: 1}
  ]
```

## Syncing

```sh
mix druid.compaction.render
mix druid.compaction.sync --dry-run
mix druid.compaction.sync
```

Sync only submits configs that changed. See `Druid.Compaction` for all
options.
