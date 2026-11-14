# Ecto.Adapters.Druid

Ecto Druid [(documentation)](https://hexdocs.pm/ecto_druid) allows interacting with Druid via Ecto. It features:

* An Ecto adapter for Druid
* Modules that provide Druid's SQL functions (see `Ecto.Druid.Query`)
* Types for Druid's complex types
* A Druid API client

The library targets and is tested against Apache Druid 38.0.0.

To learn more about getting started, see the [Ecto repository](https://github.com/elixir-ecto/ecto).

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
