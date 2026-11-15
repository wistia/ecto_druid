# Retention Rules

Retention rules work the same way as [ingestion specs](ingestion_specs.md):
EEx templates in your project, values from config, and Mix tasks that sync
them.

## Templates

`priv/druid/retention/page_views_hourly.json.eex` holds the rules for the
`page_views_hourly` data source:

```eex
[
  {"type": "loadByPeriod", "period": "P2Y",
   "tieredReplicants": {<%= json @historical_tier %>: <%= @replicas %>}},
  {"type": "dropForever"}
]
```

## Configuration

```elixir
config :my_app, MyApp.DruidRepo,
  retention: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{historical_tier: "_default_tier", replicas: 2}
  ]
```

## Syncing

```sh
mix druid.retention.render
mix druid.retention.sync --dry-run
mix druid.retention.sync
```

Sync only submits rules that changed. It also refuses rules that name a tier
with no Historicals, since Druid would accept them and unload the data. See
`Druid.Retention` for the tier check and all options.
