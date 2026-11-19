# Druid API Client

`Druid.Client` sends requests to Druid's HTTP API. Each module under it builds
`Req` requests for one part of the API, which you then send with
`Druid.Client.request/2` or `Druid.Client.request!/2`:

```elixir
druid = [host: "localhost", port: 8888]

Druid.Client.Task.all(state: "running") |> Druid.Client.request!(druid)

Druid.Client.DataSource.mark_unused("wikipedia", %{"interval" => "2015-09-12/2015-09-13"})
|> Druid.Client.request!(druid)
```

A repo's config works as the connection options too:
`Druid.Client.request!(req, MyApp.DruidRepo.config())`.

| Module | API |
| --- | --- |
| `Druid.Client.SQL` | SQL queries, SQL-based ingestion, and query cancellation |
| `Druid.Client.SQL.Statement` | Asynchronous queries from deep storage |
| `Druid.Client.Native` | Native JSON queries |
| `Druid.Client.Task` | Submitting, listing, inspecting, and shutting down tasks |
| `Druid.Client.Supervisor` | Streaming ingestion and compaction supervisors |
| `Druid.Client.DataSource` | Data sources and their segments, including marking segments used or unused and kill tasks |
| `Druid.Client.Metadata` | Segments in the metadata store and segment loading |
| `Druid.Client.Compaction` | Automatic compaction configs and status |
| `Druid.Client.Retention` | Retention rules |
| `Druid.Client.Lookup` | Lookups |
| `Druid.Client.Config` | Coordinator, Broker, and Overlord worker dynamic config |
| `Druid.Client.Status` | Service health, leaders, readiness, and workers |

## Errors and retries

`request/2` returns `{:error, %Druid.Client.RequestError{}}` when Druid
answers with an error status. Druid's error code, category and message are
in `:error_code`, `:category` and `:error_message`, so you can match on
them:

```elixir
case Druid.Client.SQL.Statement.status(id) |> Druid.Client.request(druid) do
  {:ok, status} -> status
  {:error, %Druid.Client.RequestError{error_code: "notFound"}} -> nil
end
```

A request that gets no response returns the `Req.TransportError`.

`Req` retries a GET or HEAD that fails with a transient error (a 408, 429,
500, 502, 503 or 504, or no response) three times over about seven seconds.
Pass `:retry`, `:max_retries` or `:retry_delay` to change that:

```elixir
Druid.Client.Task.all() |> Druid.Client.request(druid ++ [retry: false])
```

Health and readiness checks from `Druid.Client.Status` aren't retried, so a
service that is down or not ready is reported at once.
`Druid.Client.Task.statuses/1` is retried even though it is a POST, because
it only reads.
