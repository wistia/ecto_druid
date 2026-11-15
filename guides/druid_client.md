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
