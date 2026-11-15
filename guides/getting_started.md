# Getting Started

Ecto Druid lets you query [Apache Druid](https://druid.apache.org/) with Ecto.
It targets and is tested against Apache Druid 38.0.0.

## Installation

Add the dependency:

```elixir
# mix.exs
defp deps do
  [{:ecto_druid, "~> 0.6.0"}]
end
```

Define a repo that uses the adapter:

```elixir
defmodule MyApp.DruidRepo do
  use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Druid
end
```

## Configuration

Point the repo at a Druid Broker or Router and add it to your supervision tree:

```elixir
config :my_app, MyApp.DruidRepo,
  host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
  port: 8888,
  context: %{sqlTimeZone: "Etc/UTC"}
```

See `Ecto.Adapters.Druid` for every option.

## What the repo can do

The repo is read-only. `all`, `one` and the other query functions work.
Updates, deletes and migrations don't. Data gets into Druid through ingestion
(see the [Ingestion Specs](ingestion_specs.md) guide and
`Druid.Client.SQL.insert/3`).

Formatter users should add `import_deps: [:ecto_druid]` to `.formatter.exs` so
the `Ecto.Druid.Schema` macros can be written without parentheses.

## Next steps

* [Querying](querying.md): `Ecto.Query`, Druid SQL functions, joins and query context
* [Native Queries](native_queries.md): Druid's JSON query language
* [Ingestion Specs](ingestion_specs.md): supervisor specs as EEx templates
* [Compaction](compaction.md): automatic compaction configs
* [Retention Rules](retention.md)
* [Lookups](lookups.md)
* [System Tables](system_tables.md): `sys.*` and `INFORMATION_SCHEMA.*`
* [Druid API Client](druid_client.md): Druid's HTTP API
