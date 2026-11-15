# Native Queries

Druid also has a [native JSON query language](https://druid.apache.org/docs/latest/querying/),
which Druid SQL is translated into. Use it for query types or options SQL
doesn't expose.

`native_query/2` on the repo sends a query map to the same host and returns
the decoded JSON response, with string keys:

```elixir
MyApp.DruidRepo.native_query(%{
  queryType: "topN",
  dataSource: "wikipedia",
  intervals: ["2016-06-27/2016-06-28"],
  granularity: "all",
  dimension: "channel",
  metric: "edits",
  threshold: 10,
  aggregations: [%{type: "count", name: "edits"}],
  context: %{timeout: 30_000}
})
#=> [%{"timestamp" => "2016-06-27T00:00:00.000Z",
#      "result" => [%{"channel" => "#en.wikipedia", "edits" => 6650}, ...]}]
```

An `Ecto.Druid.Interval` encodes to its ISO 8601 string, so you can also write
`intervals: [Ecto.Druid.Interval.last(day: 1)]`.

A native query carries its context in the query map, so the repo's
`:context` config doesn't apply.

`Druid.Client.Native` also builds requests to list the segments a native query
would read (`candidates/1`) and to cancel a running query by its `queryId`
(`cancel/1`).
