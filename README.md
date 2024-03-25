# Ecto.Adapters.Druid

Ecto Druid [(documentation)](https://hexdocs.pm/ecto_druid) allows interacting with Druid via Ecto. It features:

* An Ecto adapter for Druid
* A module that provides Druid's SQL functions
* Types for Druid's complex types
* A Druid API client

To learn more about getting started, see the [Ecto repository](https://github.com/elixir-ecto/ecto).

## Running Tests

```sh
git clone https://github.com/wistia/ecto_druid.git
cd ecto_druid

# Start druid
docker compose up -d druid

# Wait for druid to start up, then load data into it
curl "http://localhost:8888/druid/indexer/v1/task" \
  --header 'Content-Type: application/json' \
  -d @ingestion_spec.json

# Once the data has loaded
mix test
```
