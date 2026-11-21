# Compaction

Druid runs automatic compaction in one of two ways, depending on the
cluster's `useSupervisors` setting:

* **Compaction supervisors** (the default in Druid 38). Each data source's
  compaction is an `autocompact__<dataSource>` supervisor on the Overlord.
* **Coordinator duty**. The Coordinator compacts data sources on a schedule
  from their compaction configs.

Ecto Druid can manage compaction either way. Like
[ingestion specs](ingestion_specs.md), both use EEx templates in your project
with values from config, and Mix tasks that sync them:

| | Compaction configs | Compaction supervisor specs |
| --- | --- | --- |
| Module | `Druid.Compaction` | `Druid.Supervisors` |
| Templates | `priv/druid/compaction/` | `priv/druid/supervisors/` |
| Works with supervisors | Yes | Yes |
| Works on the Coordinator | Yes | No |

Pick one for each data source. In particular, `prune: true` in either module
removes the compaction the other defines.

## Compaction configs

`Druid.Compaction` uses Druid's compaction config API, which works in both
modes. With supervisors, Druid turns each config into the data source's
`autocompact__` supervisor.

### Templates

Each template in `priv/druid/compaction/` is the compaction config of the
data source it's named after. `priv/druid/compaction/page_views_hourly.json.eex`
configures `page_views_hourly`. Leave out `"dataSource"`; it's set from the
file name. The schema helpers work here too:

```eex
{
  "skipOffsetFromLatest": "P1D",
  "granularitySpec": {"segmentGranularity": "DAY"},
  "dimensionsSpec": <%= dimensions_spec MyApp.PageViewsHourly %>,
  "metricsSpec": <%= metrics_spec MyApp.PageViewsHourly, combining: true %>,
  "tuningConfig": {"maxNumConcurrentSubTasks": <%= @max_subtasks %>}
}
```

`combining: true` uses the combining form of each metric, which re-aggregates
the stored columns rather than reading the original input fields.

If the schema declares [projections](ingestion_specs.md#projections), add
them to the config with the `projections` helper, so compaction builds them
into the segments it rewrites: data ingested before a projection was added,
and segments written by SQL-based ingestion, which doesn't build them:

```eex
  "projections": <%= projections MyApp.PageViewsHourly %>,
```

### Configuration

```elixir
config :my_app, MyApp.DruidRepo,
  compaction: [
    # The compaction API lives on the Router/Overlord, not the Broker.
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{max_subtasks: 1},
    specs: %{"page_views_hourly" => %{max_subtasks: 3}}
  ]
```

### Syncing

```sh
mix druid.compaction.render
mix druid.compaction.sync --dry-run
mix druid.compaction.sync
```

In a release, call `Druid.Compaction.sync(MyApp.DruidRepo)` instead.

Druid stores compaction configs with every default filled in, so sync treats
a config as unchanged when every value in the template matches Druid's.
Removing a setting from a template therefore isn't seen as a change. Sync with
`--force` (`force: true`) after removing one. See `Druid.Compaction` for all
options.

## Compaction supervisor specs

On a cluster that runs compaction supervisors, you can instead write the
supervisor spec yourself and manage it alongside your ingestion specs.
Put it in `priv/druid/supervisors/` with `"type": "autocompact"`:

```eex
{
  "type": "autocompact",
  "spec": {
    "dataSource": "page_views_hourly",
    "skipOffsetFromLatest": "P1D",
    "granularitySpec": {"segmentGranularity": "DAY"},
    "dimensionsSpec": <%= dimensions_spec MyApp.PageViewsHourly %>,
    "metricsSpec": <%= metrics_spec MyApp.PageViewsHourly, combining: true %>,
    "tuningConfig": {"maxNumConcurrentSubTasks": <%= @max_subtasks %>}
  }
}
```

It takes its values from the `supervisors:` config and syncs with
`mix druid.supervisors.sync`, like any other supervisor spec. Druid names the
supervisor `autocompact__page_views_hourly`. See
[Ingestion Specs](ingestion_specs.md) and `Druid.Supervisors`.
