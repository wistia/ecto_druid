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

## Request events

Every HTTP request `Druid.Client` sends runs in a `[:druid, :request]` span.
This covers repo queries, `Druid.Tasks`, `Druid.Supervisors`,
`Druid.Lookups`, `Druid.Retention`, `Druid.Compaction` and their Mix
tasks, and any request you send with `Druid.Client.request/2` yourself. A
repo query that polls, like one from deep storage, sends several requests,
and each gets its own span.

* `[:druid, :request, :start]` - Before the request is sent. Measures
  `:system_time` and `:monotonic_time`.
* `[:druid, :request, :stop]` - When Druid responds, whatever the status.
  Measures the `:duration` and the `:decode_time` spent decoding the
  response body.
* `[:druid, :request, :exception]` - When no response comes back, for
  example on a timeout or refused connection. Measures the `:duration`.

Times are in `:native` units. Every event's metadata has:

* `:method` - The HTTP method, such as `:get`.
* `:scheme`, `:host`, `:port` - Where the request went.
* `:path` - The request path, such as `"/druid/v2/sql"`.
* `:repo` - The repo, for requests sent for one.
* Anything in the call's `:telemetry_metadata` option.

`:stop` adds the response `:status`, and `:exception` adds `:kind`,
`:reason` and `:stacktrace`. Credentials and request bodies are never in
the metadata.

Req doesn't emit telemetry. Finch, which sends the requests, emits its own
[events](https://hexdocs.pm/finch/Finch.Telemetry.html) for connection
pooling, connecting, sending and receiving. Each repo's Finch pool is named
after the repo, such as `MyApp.DruidRepo.Finch`, which is the `:name` in
their metadata.

## Waiting for tasks and statements

Ingestion tasks and queries from deep storage can run for minutes. Two spans
cover the whole wait, around the `[:druid, :request]` spans of each poll.
Both measure `:duration` in `:native` units.

### `[:druid, :task, :await]`

`Druid.Tasks.await/3`, and so `Druid.Tasks.run/3` and `insert_all/3`, wait
for a task in this span.

* `:start` metadata: `:repo`, `:task_id`, `:wait_for_segments`.
* `:stop` adds `:result` (`{:ok, status}` or `{:error, exception}`), the
  task's final `:state` (`"SUCCESS"` or `"FAILED"`, or `nil` when the wait
  timed out or a request failed) and its `:data_source` when known.

A failed or timed-out task ends with `:stop`, since `await/3` returns the
error rather than raising it.

### `[:druid, :statement, :await]`

A repo query from deep storage submits a statement and waits for it in this
span. The result pages are read afterward.

* `:start` metadata: `:repo`, `:query_id` and the `:timeout` in milliseconds.
* `:stop` adds the final `:state` and the `:num_rows` the results hold.
* `:exception` adds `:kind`, `:reason` and `:stacktrace`. A statement that
  fails, is canceled or runs past its timeout raises
  `Ecto.Adapters.Druid.StatementError`, so it ends here.

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
