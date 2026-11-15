# Lookups

Lookups work the same way as [ingestion specs](ingestion_specs.md): EEx
templates in your project, values from config, and Mix tasks that sync them.
Once synced, query them with `lookup/3` or by joining them (see
[Querying](querying.md)).

## Templates

`priv/druid/lookups/countries.json.eex` defines the `countries` lookup. A
template renders only the lookup's `lookupExtractorFactory`. The library
manages the version and only bumps it when the lookup changes:

```eex
{"type": "map", "map": <%= json @countries %>}
```

Lookups go in the `__default` tier, or the one set by the `:tier` option. To put a lookup in another tier, place
its template in a directory named after the tier, such as
`priv/druid/lookups/realtime/countries.json.eex`.

## Configuration

```elixir
config :my_app, MyApp.DruidRepo,
  lookups: [
    host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
    port: 8888,
    assigns: %{countries: %{"US" => "United States"}}
  ]
```

## Syncing

```sh
mix druid.lookups.render
mix druid.lookups.sync --dry-run
mix druid.lookups.sync
```

Sync only submits lookups that changed. See `Druid.Lookups` for all options.
