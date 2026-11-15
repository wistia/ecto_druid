# Wiki Explorer

A Phoenix LiveView app that uses [ecto_druid](..) to explore a day of
Wikipedia edits stored in Apache Druid.

It shows how to:

* Define a Druid repo, and describe a data source with the `Ecto.Druid.Schema`
  macros `timestamp`, `dimension` and `metric`
  ([`DruidRepo`](lib/wiki_explorer/druid_repo.ex),
  [`Wiki.Edit`](lib/wiki_explorer/wiki/edit.ex))
* Write Ecto queries that use Druid SQL functions: `time_in_interval`,
  `time_floor`, HLL and Theta sketches for distinct counts, quantile sketches,
  `icontains_string` and filtered aggregations ([`Wiki`](lib/wiki_explorer/wiki.ex))
* Define a lookup with `Ecto.Druid.Lookup`, sync it to Druid from an EEx template,
  and use it with `lookup/3` or query it like a table
  ([`Wiki.ChannelLanguages`](lib/wiki_explorer/wiki/channel_languages.ex),
  [template](priv/druid/lookups/channel_languages.json.eex))
* Read Druid's system tables with the bundled `sys.*` and
  `INFORMATION_SCHEMA` schemas ([`Cluster`](lib/wiki_explorer/cluster.ex))
* Run a native `topN` query with `native_query/1`
* Generate an ingestion task's `dataSchema` from that schema, submit it and
  poll its status with `Druid.Client`
  ([`mix wiki_explorer.ingest`](lib/mix/tasks/wiki_explorer.ingest.ex))

## Running it

The app depends on ecto_druid by path (`{:ecto_druid, path: ".."}`), so it
always runs against the code in this repository. Your own app would use
`{:ecto_druid, "~> 0.6"}` instead.

1. Start Druid with the docker-compose file at the root of this repository:

   ```sh
   cd ..
   docker compose up -d druid
   ```

   Wait until `curl localhost:9888/status/health` returns `true`.

2. Install dependencies and build assets:

   ```sh
   cd example
   mix setup
   ```

3. Create the lookup and load the sample data:

   ```sh
   mix druid.setup
   ```

   This runs `mix druid.lookups.sync`, then `mix wiki_explorer.ingest`, which
   submits a batch ingestion task for the `wiki_edits` data source and waits
   until it can be queried. The task's `dataSchema` is generated from
   [`Wiki.Edit`](lib/wiki_explorer/wiki/edit.ex). Druid downloads
   the data from druid.apache.org, so the container needs internet access.

   Druid pushes lookups to its services every couple of minutes. Until it
   does, queries that use the lookup fail with `Lookup [channel_languages] not
   found`.

4. Start the server:

   ```sh
   mix phx.server
   ```

   Then visit [localhost:4000](http://localhost:4000).

The app connects to Druid's Router at `localhost:9888`, the port the compose
file maps it to. Set `DRUID_HOST` and `DRUID_PORT` to point it somewhere else
(see [`config/runtime.exs`](config/runtime.exs)).

## Pages

* **Overview** (`/`): headline numbers, edits per hour, and the top channels,
  pages, editors and countries, filtered by channel and whether to include
  robots. It also shows the SQL that the headline query sends to Druid.
* **Pages** (`/pages`): search page titles as you type, and open a page to
  see its editors and recent edits.
* **Druid** (`/druid`): the data source's columns and segments, the cluster's
  services, the lookup's contents, and a native `topN` query.

## Tests

```sh
mix test                  # SQL generation only, no Druid needed
mix test --include druid  # also renders each page against Druid
```

The `druid` tests need the sample data from `mix druid.setup`.
