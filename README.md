# Ecto.Adapters.Druid

[![Hex.pm](https://img.shields.io/hexpm/v/ecto_druid.svg)](https://hex.pm/packages/ecto_druid)
[![Documentation](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ecto_druid)

Ecto Druid allows interacting with [Apache Druid](https://druid.apache.org/)
via Ecto. It features:

* An Ecto adapter for Druid
* Modules that provide Druid's SQL functions (see `Ecto.Druid.Query`)
* Types for Druid's complex types
* Schemas for Druid's system tables (`sys.*` and `INFORMATION_SCHEMA.*`)
* A Druid API client
* `Repo.insert_all/3` through SQL-based ingestion (`INSERT` and `REPLACE`)
* Supervisor specs (Kafka ingestion), batch ingestion tasks, compaction
  configs, retention rules and lookups managed as EEx templates, with
  per-environment values from config

The library targets and is tested against Apache Druid 38.0.0.

## Installation

```elixir
# mix.exs
defp deps do
  [{:ecto_druid, "~> 0.6.0"}]
end

defmodule MyApp.DruidRepo do
  use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Druid
end
```

```elixir
config :my_app, MyApp.DruidRepo,
  host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
  port: 8888
```

```elixir
import Ecto.Query
use Ecto.Druid.Query

MyApp.DruidRepo.all(
  from p in "page_views_hourly",
    where: time_in_interval(p.__time, "2026-11-01/P1W"),
    group_by: p.country,
    select: %{country: p.country, views: count()}
)
```

## Guides

* [Getting Started](guides/getting_started.md)
* [Querying](guides/querying.md)
* [Native Queries](guides/native_queries.md)
* [Ingestion Specs](guides/ingestion_specs.md)
* [SQL Ingestion](guides/sql_ingestion.md)
* [Compaction](guides/compaction.md)
* [Retention Rules](guides/retention.md)
* [Lookups](guides/lookups.md)
* [System Tables](guides/system_tables.md)
* [Druid API Client](guides/druid_client.md)
* [Telemetry](guides/telemetry.md)
* [Upgrading](guides/upgrading.md)

## Example app

[`example/`](example) is a Phoenix LiveView app that explores a day of
Wikipedia edits with ecto_druid: schemas, Druid SQL functions, sketches,
lookups, system tables, native queries and ingestion. See its
[README](example/README.md) to run it.

## Running Tests

`mix test` runs the unit tests, which don't need Druid. Tests that talk to a
running Druid are tagged `:druid` and excluded by default.

```sh
git clone https://github.com/wistia/ecto_druid.git
cd ecto_druid

mix test
```

To run the Druid tests too, start Druid and load the sample data first:

```sh
# Start druid
docker compose up -d --build druid

# Wait for druid to start up, then load data into it
curl "http://localhost:9888/druid/indexer/v1/task" \
  --header 'Content-Type: application/json' \
  -d @ingestion_spec.json

# Once the data has loaded
mix test --include druid

# Or only the Druid tests
mix test --only druid
```

The compose file maps services to non-default host ports so they don't clash
with other local containers: Druid router on 9888, Druid broker on 9082,
Postgres on 6432, ZooKeeper on 3181, and SeaweedFS (S3 API) on 9900.

Starting Druid also starts Kafka, which the streaming ingestion test writes to
with `docker compose exec`, so run `mix test` from the repository root.
