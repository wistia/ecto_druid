# Testing

Code that queries Druid can be tested two ways:

* **With stubs**, where `Ecto.Druid.Test` answers the repo's queries with
  rows the test gives. These tests are fast, need no cluster, and can run
  `async: true`. They check what your code does with Druid's answers, and
  what it asks.
* **Against a real Druid**, which also checks that Druid plans and answers
  the queries the way you expect. These are slower and need a cluster, so
  they're usually tagged and run separately.

Most of this guide covers stubs. [Stubbed and real-Druid tests](#stubbed-and-real-druid-tests)
shows how to keep both kinds in one suite, and [Loading fixtures](#loading-fixtures)
how to give the real-Druid tests data to query.

## Setup

`Ecto.Druid.Test` is built on `Req.Test`, which needs the `:plug` package.
Add it for tests if you don't have it:

```elixir
# mix.exs
{:plug, "~> 1.15", only: :test}
```

Send the repo's requests to `Req.Test` in the test config, named after the
repo:

```elixir
# config/test.exs
config :my_app, MyApp.DruidRepo, plug: {Req.Test, MyApp.DruidRepo}
```

Nothing then reaches Druid: a test that sends a query without stubbing the
repo fails. The `:host` and `:port` can stay as they are, for the runs
against a real Druid described [below](#stubbed-and-real-druid-tests).

## Stubbing queries

Suppose a context module counts a day's edits by channel:

```elixir
defmodule MyApp.Wiki do
  import Ecto.Query
  use Ecto.Druid.Query

  def edits_by_channel(day) do
    MyApp.DruidRepo.all(
      from e in "wikipedia",
        where: time_in_interval(e.__time, ^Ecto.Druid.Interval.new(day, Date.add(day, 1))),
        group_by: e.channel,
        order_by: [desc: count()],
        select: %{channel: e.channel, edits: count()}
    )
  end
end
```

A test stubs the repo with a function that gets each query and returns its
rows, as lists of values in the order the query selects them:

```elixir
defmodule MyApp.WikiTest do
  use ExUnit.Case, async: true

  test "counts edits by channel" do
    Ecto.Druid.Test.stub(MyApp.DruidRepo, fn %{type: :sql} ->
      [["#en.wikipedia", 11549], ["#de.wikipedia", 2523]]
    end)

    assert MyApp.Wiki.edits_by_channel(~D[2016-06-27]) == [
             %{channel: "#en.wikipedia", edits: 11549},
             %{channel: "#de.wikipedia", edits: 2523}
           ]
  end
end
```

The stub sends the rows the way Druid does, so the repo loads them as it
would Druid's: timestamps into `DateTime`s, sketches into Base64 strings,
error bounds into `Ecto.Druid.Estimate`s, and so on. `Repo.stream/2`
streams them, and `deep_storage: true` queries get them through the deep
storage API, as `:statement` requests.

## Checking the query

The function gets an `Ecto.Druid.Test.Request` with the SQL, its parameters
and its context, so a test can match on what was asked:

```elixir
Ecto.Druid.Test.stub(MyApp.DruidRepo, fn %{query: sql, params: [interval]} ->
  assert sql =~ "GROUP BY"
  assert interval == "2016-06-27/2016-06-28"
  []
end)
```

To check that a query was sent at all, or how many times, send a message
from the stub:

```elixir
test = self()

Ecto.Druid.Test.stub(MyApp.DruidRepo, fn request ->
  send(test, {:druid, request})
  []
end)

MyApp.Wiki.edits_by_channel(~D[2016-06-27])
assert_received {:druid, %{type: :sql}}
refute_received {:druid, _}
```

A stub only checks your side. It accepts SQL that Druid can't plan, so
keep a test against a real Druid for queries where that's a risk.

## Failures

Return `{:error, category, message}` to answer the way Druid does when a
query fails, and `:timeout` to time the request out:

```elixir
Ecto.Druid.Test.stub(MyApp.DruidRepo, fn _ ->
  {:error, :capacity_exceeded, "Too many concurrent queries"}
end)

assert_raise Druid.Client.RequestError, fn -> MyApp.Wiki.edits_by_channel(~D[2016-06-27]) end
```

## Native queries and ingestion

Native queries are `:native` requests. Return the rows as `native_query/2`
returns them, keyed by column, and the stub builds the response Druid sends
for the query's type:

```elixir
Ecto.Druid.Test.stub(MyApp.DruidRepo, fn %{type: :native, query: %{"queryType" => "timeseries"}} ->
  [%{"__time" => "2016-06-27T00:00:00.000Z", "edits" => 24433}]
end)
```

`Repo.insert_all/3`, `delete_all/2` and `update_all/3` are `:ingest`
requests. Return `:ok`, or `{:failed, message}` for a task that fails. The
stub answers the task status and segment loading checks itself, so
`wait_for_segments: true` returns at once.

See `Ecto.Druid.Test` for every request type and return value.

## Other processes

Stubs belong to the test process. Processes that know they were started for
it find them too: tasks the test starts, and LiveViews under
`Phoenix.LiveViewTest`, which record the test as their caller. A process
that was already running, such as a GenServer in your supervision tree,
needs to be allowed:

```elixir
Req.Test.allow(MyApp.DruidRepo, self(), Process.whereis(MyApp.DashboardCache))
```

Or share the test's stubs with every process, in a test module that isn't
async:

```elixir
setup {Req.Test, :set_req_test_to_shared}
```

## Case templates

Stubs need no setup: there's no sandbox to check out or connection to
share, and a test's stubs go away with it. So a test that queries Druid
doesn't need a Druid case template. It can use `ExUnit.Case`, or the
template it already uses, such as your `ConnCase` for a LiveView.

If you add Druid helpers to a case template, leave `use Ecto.Druid.Query`
out of it. It replaces a few `Kernel` functions, such as `length/1`,
`div/2` and `round/1`, with SQL macros that compile only inside a query, so
every test that calls `length(rows)` would fail to compile. Build queries in
your app's modules and call those from tests, or `use Ecto.Druid.Query` only
in the test modules that build queries.

## Stubbed and real-Druid tests

We suggest keeping both kinds of test in one suite and running them
separately: the stubbed tests on every `mix test`, and the real-Druid tests
when a cluster is available, such as in CI. The plug is repo config, so a run
is one or the other, and one environment variable picks which.

Tag the tests that need Druid:

```elixir
defmodule MyApp.WikiDruidTest do
  use ExUnit.Case
  @moduletag :druid

  test "Druid plans the edits query" do
    assert [_ | _] = MyApp.Wiki.edits_by_channel(~D[2016-06-27])
  end
end
```

When `DRUID_TESTS` is set, turn the stub off:

```elixir
# config/test.exs
config :my_app, MyApp.DruidRepo,
  host: "localhost",
  port: 8888,
  plug: if(System.get_env("DRUID_TESTS"), do: nil, else: {Req.Test, MyApp.DruidRepo})
```

And run only the `:druid` tests:

```elixir
# test/test_helper.exs
if System.get_env("DRUID_TESTS") do
  ExUnit.start(include: [:druid], exclude: [:test])
else
  ExUnit.start(exclude: [:druid])
end
```

Excluding `:test` excludes every test, and including `:druid` brings the
tagged ones back. Without it, the stubbed tests would run in the same pass,
with their queries going to Druid, and fail or, worse, pass by accident.

Run the stubbed tests:

```sh
mix test
```

And the tests against Druid:

```sh
DRUID_TESTS=1 mix test
```

With `plug: nil`, the repo, `insert_all` and the template modules send
their requests to the configured host. In the stubbed run, any test that
queries the repo without a stub fails rather than reaching Druid. A line
number given to `mix test` overrides the exclusions, so
`DRUID_TESTS=1 mix test test/my_app/wiki_test.exs:12` runs that test
against Druid even when it's a stubbed one.

Don't try to mix the two in one run with a second repo started without the
plug. `insert_all`, `Druid.Tasks` and the other template modules read the
repo module's config, so they would still send their requests to the stub.

## Loading fixtures

Ingesting data takes Druid several seconds, so rather than have each
real-Druid test load its own, load it once when the suite starts, with
`Ecto.Druid.Fixtures`:

```elixir
# test/test_helper.exs
if System.get_env("DRUID_TESTS") do
  Ecto.Druid.Fixtures.load!(MyApp.DruidRepo, [
    {MyApp.Edit, "test/fixtures/edits.jsonl"}
  ])

  ExUnit.start(include: [:druid], exclude: [:test])
else
  ExUnit.start(exclude: [:druid])
end
```

`MyApp.Edit` is an `Ecto.Druid.Schema` whose source is `"wikipedia"`. The
file holds input records, one JSON object per line, keyed the way your
ingestion reads them:

```json
{"timestamp": "2016-06-27T01:00:00Z", "channel": "#en.wikipedia", "page": "Main Page"}
{"timestamp": "2016-06-27T02:00:00Z", "channel": "#en.wikipedia", "page": "Elixir"}
{"timestamp": "2016-06-27T02:30:00Z", "channel": "#de.wikipedia", "page": "Berlin"}
```

They're ingested through the schema's generated `dataSchema`, so `from:`
transforms, rollup and sketch metrics apply as they do in production. Rows
can also be a list of maps, and a data source without a schema can be given
its `dataSchema` directly; see `Ecto.Druid.Fixtures`.

Each load replaces everything in the data source, so every run starts from
the same data, and tests can assert exact results:

```elixir
test "counts edits by channel" do
  assert MyApp.Wiki.edits_by_channel(~D[2016-06-27]) == [
           %{channel: "#en.wikipedia", edits: 2},
           %{channel: "#de.wikipedia", edits: 1}
         ]
end
```

The data sources load at the same time. On a small local cluster, a load
takes about ten seconds.

A few things keep fixture data useful:

* **Tests only read it.** A test that writes to a fixture data source
  changes it for every test after it. Tests that ingest should use a data
  source of their own, and remove it when they're done.
* **Dates are fixed.** Code that asks for "the last 7 days" should take its
  time window as an argument, so a test can pass one that holds the
  fixtures.
* **Fixtures stay small.** The rows are sent inside the task spec, which
  Druid stores in its metadata database, so thousands of rows are fine but
  millions aren't.

## Other Druid APIs

`Ecto.Druid.Test` answers the queries a repo sends. `Druid.Tasks`,
`Druid.Supervisors` and the other modules send their requests to the repo's
plug too, unless their own config sets one. To test those, give that module
its own plug in config, and stub it with `Req.Test.stub/2`, which takes any
plug:

```elixir
# config/test.exs
config :my_app, MyApp.DruidRepo,
  plug: {Req.Test, MyApp.DruidRepo},
  supervisors: [plug: {Req.Test, MyApp.DruidSupervisors}]
```
