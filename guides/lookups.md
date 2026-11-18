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

## Generating lookups from schemas

A lookup schema can also describe how the lookup is loaded. Its template then
generates the factory with `lookup_factory`, the way supervisor templates use
`data_schema`. The schema holds what is the same everywhere, and the template
passes what changes between environments.

A map lookup only needs its values:

```eex
<%= lookup_factory MyApp.Countries, map: @countries %>
```

A JDBC lookup names its table in the schema. The key and value columns
default to the field names:

```elixir
defmodule MyApp.Countries do
  use Ecto.Druid.Lookup,
    key: :code,
    value: :name,
    injective: true,
    jdbc: [table: "countries", filter: "active = true"]
end
```

The template supplies the connection:

```eex
<%= lookup_factory MyApp.Countries, connector: @lookup_db, poll_period: "PT10M" %>
```

```elixir
config :my_app, MyApp.DruidRepo,
  lookups: [
    assigns: %{
      lookup_db: %{
        uri: System.get_env("LOOKUP_DB_URI"),
        user: "druid",
        # Druid reads the password from its own environment
        password: {:env, "LOOKUP_DB_PASSWORD"}
      }
    }
  ]
```

JDBC lookups need Druid's `druid-lookups-cached-global` extension and the
database's JDBC driver.

`lookup_factory` raises if the template's name doesn't match the schema's
lookup, so renaming one without the other fails at render time instead of
leaving queries pointed at a lookup that doesn't exist. See
`Ecto.Druid.Lookup.Spec.factory/2` for every option.

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

## Waiting for lookups to load

Druid loads a new or changed lookup onto its nodes in the background, so
for a while after a sync, queries can miss it or fail with "Lookup not
found". To wait until every node in the lookup's tier has the current
version, pass `wait: true`:

```elixir
Druid.Lookups.sync(MyApp.DruidRepo, wait: true, timeout: 60_000)
```

```sh
mix druid.lookups.sync --wait --timeout 60
```

A lookup that doesn't load in time is returned as
`{:error, lookup, %Druid.Lookups.Error{reason: :timeout}}`, with the nodes that
hadn't loaded it. To wait for lookups you didn't just sync, use
`Druid.Lookups.await/3`:

```elixir
:ok = Druid.Lookups.await(MyApp.DruidRepo, ["countries", "realtime/channels"], timeout: 60_000)
```

The nodes include Brokers, Historicals, and streaming ingestion tasks, unless
a task's spec sets `"lookupLoadingMode": "NONE"`. Queries that use a lookup
fail on rows such a task still holds.

The Coordinator only checks what the nodes have loaded every
`druid.manager.lookups.period`, which is two minutes by default, so waiting
can take up to four. On clusters used for tests, set it lower:

```properties
druid.manager.lookups.period=5000
```
