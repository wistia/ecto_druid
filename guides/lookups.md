# Lookups

Lookups work the same way as [ingestion specs](ingestion_specs.md): EEx
templates in your project, values from config, and Mix tasks that sync them.
Once synced, query them through a lookup schema (below), with `lookup/3`, or
by joining them (see [Querying](querying.md)).

## Lookup schemas

Define a schema for a lookup with `Ecto.Druid.Lookup`. It reads the lookup
named after the module (`countries` here) from Druid's `lookup` schema:

```elixir
defmodule MyApp.Countries do
  use Ecto.Druid.Lookup, key: :code, value: :name
end
```

Fetch from it, join it, or pass it to `lookup/2,3` in place of the lookup's
name:

```elixir
MyApp.DruidRepo.get(MyApp.Countries, "US")
#=> %MyApp.Countries{code: "US", name: "United States"}

from p in MyApp.PageViewsHourly,
  join: c in MyApp.Countries, on: c.code == p.country,
  group_by: c.name,
  select: {c.name, sum(p.views)}

from p in MyApp.PageViewsHourly,
  group_by: 1,
  select: {lookup(p.country, MyApp.Countries, "Unknown"), sum(p.views)}
```

The schema also defines `MyApp.Countries.lookup/1,2`, which do the same once
you `require MyApp.Countries`.

`:key` and `:value` name the fields and default to `:k` and `:v`, Druid's
column names. Pass `name: "..."` when the lookup's name doesn't match the
module.

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
