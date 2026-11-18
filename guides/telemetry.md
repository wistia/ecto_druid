# Telemetry

ecto_druid emits [Telemetry](https://hexdocs.pm/telemetry/) events for the
queries a repo sends and logs each query, as Ecto's SQL adapters do. Metrics,
tracing and LiveDashboard handlers written for a SQL repo work with a Druid
repo too.

## Query events

Every query a repo sends to Druid emits one event, named after the repo's
`:telemetry_prefix`. For `MyApp.DruidRepo` that is
`[:my_app, :druid_repo, :query]`. These calls emit it:

* `all/2`, `one/2` and the other read functions, for SQL queries to the
  Broker or from deep storage
* `stream/2`, when the stream is first enumerated
* `insert_all/3`
* `native_query/2` and `native_query!/2`
* `to_native/2`

```elixir
:telemetry.attach(
  "druid-query-logger",
  [:my_app, :druid_repo, :query],
  &MyApp.Telemetry.handle_druid_query/4,
  nil
)
```

### Measurements

All times are in `:native` units. Convert them with `System.convert_time_unit/3`.

* `:query_time` - Time spent sending the query and waiting for Druid. For a
  query from deep storage, this includes polling until it finishes. For
  `insert_all/3`, it includes waiting for the ingestion task.
* `:decode_time` - Time spent decoding Druid's JSON responses and, for
  native queries, flattening the results into rows.
* `:total_time` - `query_time` plus `decode_time`.

There is no `:queue_time`. Druid queries go over HTTP, and Finch's
`[:finch, :queue, :stop]` event reports the time spent waiting for a
connection.

### Metadata

* `:type` - `:druid_sql_query` for SQL, including `insert_all/3` and
  `to_native/2`, or `:druid_native_query` for `native_query/2`.
* `:repo` - The repo.
* `:query` - The SQL statement, or the native query encoded as JSON.
* `:native_query` - The native query as a map. Only for `native_query/2`.
* `:params` - The parameters sent to Druid, as `%{type: ..., value: ...}`
  maps. `nil` for native queries, which carry their values inline.
* `:cast_params` - The parameters before they were dumped, when Ecto gives
  them.
* `:source` - The table the query reads, or `nil` when it reads a subquery,
  a join of several, or a native `union` data source.
* `:query_id` - The ID Druid knows the query by: the SQL query's
  `sqlQueryId` or the native query's `queryId`. Each query gets a new one
  unless its `:context` sets it. Search Druid's request logs and metrics for
  this ID, or cancel the query with it.
* `:context` - The query context sent to Druid.
* `:deep_storage` - The deep storage options for a query from deep storage,
  or `nil` for one the Broker answered.
* `:result` - `{:ok, %{num_rows: n, rows: rows}}` or `{:error, exception}`.
  `rows` is `nil` for `insert_all/3` and for a deep storage stream, whose
  pages are read after the event.
* `:stacktrace` - The caller's stacktrace, when the repo is configured with
  `stacktrace: true` or the call passes it.
* `:options` - The call's `:telemetry_options`.

### Options

Every repo call that queries Druid takes:

* `:telemetry_event` - Emit the event under this name instead. Pass `nil` to
  skip it.
* `:telemetry_options` - A keyword list passed through to the event's
  `:options` metadata, for example to tag a query in metrics.
* `:stacktrace` - Include the caller's stacktrace in the event and log line.

## Logging

Each query is logged at `:debug` by default, with its result, source,
timings, statement and parameters:

```text
[debug] QUERY OK source="wikipedia" db=12.4ms decode=1.3ms
SELECT w0."page" FROM "wikipedia" AS w0 WHERE (w0."added" > ?) [10]
```

Set the repo's `:log` option to another level, or to `false` to turn query
logging off. A `:log` option on a call overrides it for that query:

```elixir
config :my_app, MyApp.DruidRepo, log: :info

MyApp.DruidRepo.all(query, log: false)
```
