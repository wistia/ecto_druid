# AGENTS.md

Guidance for coding agents working on ecto_druid, an open-source Ecto adapter
and HTTP client for [Apache Druid](https://druid.apache.org/), published on
Hex. It targets and is tested against **Druid 38.0.0**.

## Ground rules

- **This is a public package. Never write internal names into it.** That
  covers private repo names, datasource and topic names, hostnames, tiers,
  config values and column names, in code, docs, tests, fixtures, examples,
  commit messages and PR descriptions. You may read a private codebase for
  ideas. Anything written here uses generic names such as `events`,
  `page_views`, `wikipedia` or `example.com`. Check the diff before you commit.
- **Confirm a bug is real before fixing it.** Reproduce it against the local
  Druid or with a test, and show the new test fails on the old code. If a
  reported problem or review finding turns out to be wrong, say so plainly and
  drop it. Several have been wrong before.
- **Report what you didn't run.** For example: tests tagged `:druid`, the
  streaming test, or CI. Give real test counts.

## Layout

| Path | What it is |
| --- | --- |
| `lib/ecto/adapters/druid.ex` | The Ecto adapter: `all`, `stream`, `insert_all`, `delete_all`, `native_query`, `to_native`, deep-storage statements, cancellation |
| `lib/ecto/adapters/druid/query.ex` | Ecto query → Druid SQL |
| `lib/ecto/adapters/druid/ingest.ex` | `insert_all` / `delete_all` through SQL-based ingestion (`INSERT` / `REPLACE`) |
| `lib/ecto/adapters/druid/types.ex` | Parameter encoding and result loading |
| `lib/ecto/druid/query.ex`, `query/*.ex` | SQL function macros, one submodule per category in Druid's docs. `use Ecto.Druid.Query` imports them all |
| `lib/ecto/druid/native*.ex` | Native query builders (filters, aggregators, post-aggregators, expressions) and result flattening |
| `lib/ecto/druid/schema.ex` | `Ecto.Druid.Schema`: the `timestamp` / `dimension` / `metric` DSL, and `dataSchema` generation |
| `lib/ecto/druid/lookup.ex` | `Ecto.Druid.Lookup` lookup schemas |
| `lib/ecto/druid/*_sketch.ex`, `estimate.ex`, `ds_histogram.ex`, `json.ex` | Ecto types for Druid's complex types |
| `lib/ecto/druid/sys/`, `information_schema/` | Schemas for system tables |
| `lib/druid/client.ex`, `client/*.ex` | Req-based request builders for Druid's HTTP API |
| `lib/druid/{supervisors,tasks,compaction,retention,lookups}.ex` | Template-and-sync workflows. They share their plumbing through `lib/druid/spec_templates.ex` |
| `lib/mix/tasks/` | `mix druid.*.render` / `sync` / `run` / `backfill` / `status` |
| `guides/` | ExDoc guides |
| `example/` | A Phoenix LiveView app that uses the library as a path dependency, with its own `mix.exs`, formatter and tests |
| `test/fixtures/` | EEx templates for the template-and-sync tests |
| `docker/`, `docker-compose.yml`, `ingestion_spec.json` | The local Druid test cluster and its sample data |

To add a SQL function, add a `sql_function name(args)` line, with an `@doc`,
to the submodule matching the category in Druid's docs.
`sql_function` is defined in `lib/ecto/druid/util.ex`. Then add a `to_sql`
test.

## Checks

Run these before calling work done. CI runs the same ones:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test                       # unit tests, no Druid needed
mix test --include druid       # also the integration tests (needs the stack below)
MIX_ENV=dev mix docs --warnings-as-errors
```

If you touched `example/`, run `mix compile`, `mix format --check-formatted`
and `mix test` inside `example/` as well. It has its own `:druid` tag.

CI (`.github/workflows/ci.yml`) has these jobs:

- format
- test, against a real Druid
- **minimum**: Elixir 1.16 / OTP 26 with the locked deps, no Druid
- docs
- the example app

The runners are pinned to `ubuntu-24.04`, and setup-beam has Hex mirror
fallbacks. The reason is in the workflow comment. Don't unpin either without
checking.

The dependency minimums in `mix.exs` were each verified. For example,
`req ~> 0.5.18` is needed for `Finch.TransportError`. Don't lower them, and
raise them only for a reason.

## Local Druid

```sh
docker compose up -d --build druid      # starts Postgres, ZooKeeper, SeaweedFS, Kafka and Druid
curl localhost:9888/druid/indexer/v1/task -H 'Content-Type: application/json' -d @ingestion_spec.json
mix test --include druid
```

- **Host ports are deliberately non-default**, so they don't collide with
  another Druid on the defaults: router 9888, broker 9082, Postgres 6432,
  ZooKeeper 3181, SeaweedFS 9900. Inside the compose network, services use
  their native ports. Keep `docker-compose.yml`, `config/config.exs` and the
  README consistent. The test repo talks to the broker on 9082. The
  supervisor, task, compaction, retention and lookup config points at the
  router on 9888.
- **The sample data isn't loaded when the ingestion task says SUCCESS.** Wait
  until `SELECT COUNT(*) FROM wikipedia` returns rows. CI's "Load the wikipedia
  sample data" step shows how.
- **Run `mix test` from the repo root.** The streaming test writes to Kafka
  with `docker compose exec`, and the compose project name comes from the
  directory.
- **The test cluster is tuned for speed.**
  - An Indexer with 8 slots replaces the MiddleManager. Each SQL ingestion
    needs 2 slots, so a small slot count deadlocks the concurrent tests.
  - The lookup, coordinator and handoff poll periods are short (see
    `docker/druid.properties`).
  - Keep these settings when editing `docker/`. Without them the suite takes
    several times longer.
- **Another checkout's stack may already be on these ports.** If you're
  changing only code, running tests against that stack is fine. Don't restart,
  rebuild or reconfigure a stack you didn't start. To test changes under
  `docker/`:
  1. Copy the repo somewhere temporary.
  2. Remap the host ports in `docker-compose.yml`, `config/` and `test/`.
  3. Run `docker compose -p <unique-name> up -d --build druid`.
  4. When you're done, run `down -v`.
- **Many "environment" failures come from a stale stack.** Examples are a stack
  with too few slots, a missing Kafka, or a bind mount into a deleted
  worktree. To tell these from real failures, run `--max-cases 1`. Clean up any
  datasources, lookups or supervisors you create while probing.

## Tests

- Tests that need Druid are tagged `@moduletag :druid` and excluded by
  default. Unit tests that check SQL generation use `TestRepo.to_sql/1`.
  Client tests use `Druid.ClientCase` and `TestPlug` to assert on the request
  Druid would receive.
- Slow integration modules are `async: true` and share `IntegrationRepo`,
  which `test_helper.exs` starts once. Modules that start the named `TestRepo`,
  sometimes with custom config, or that attach global telemetry handlers must
  stay synchronous.
- Use `start_supervised!`, not a bare `start_link`. Otherwise the next module
  finds the repo still running.
- Integration tests use their own uniquely named datasources, lookups and
  supervisors (`ecto_druid_*_test`) so that they can run concurrently.
- **Poll for real readiness, not status flags.** A task can report SUCCESS
  before its segments load. A new datasource isn't queryable until the Broker
  lists it in `INFORMATION_SCHEMA`. Lookups propagate on a timer. Use the
  library's own `await` / `wait_for_segments` helpers.
- Don't depend on the key order of maps from Ecto. For example, match
  `insert_all` columns by name.

## Design principles

These come from decisions made while building the library. Follow them unless
the user says otherwise.

- **Native queries are real native queries.**
  - `native_query/2` takes a native query map.
  - `Repo.to_native/2` exists for debugging. It isn't a path for running SQL
    as native.
  - The builders return plain maps and emit the current filter types. They
    keep the legacy `selector` and `bound` filters, which still work and have
    different null semantics.
  - Stop short of a full DSL for every query type: Druid's spec changes too
    often to keep one current.
  - Examples use pipes.
- **The native path behaves like the SQL path:**
  - `{:ok, _} | {:error, _}` and bang variants
  - automatic query ids
  - cancel on timeout
  - an opt-in `merge_context`
- **Check columns by default when a schema is given.**
  - If an `Ecto.Druid.Schema` is a native query's `dataSource`, the columns the
    query reads are checked against it, unless `check_columns: false` is
    passed.
  - Asking for the check without a schema raises. It doesn't silently skip.
  - Expressions record the columns they read, so those are checked too.
- **Convert in the macro.** `time_in_interval` always emits
  `TIME_IN_INTERVAL`. When the bounds are a literal tuple, the macro turns
  them into a string at compile time. When the bounds are pinned, the macro
  generates code that converts them at runtime. Don't add a public helper for
  this.
- **Complex types load as values you can use right away.**
  - Histograms load as lists of floats.
  - Error bounds load as `Ecto.Druid.Estimate`.
  - Raw sketches stay Base64 strings, so they can be passed back into a query.
- **Don't add a failure point for little value.** For example, `delete_all`
  returns `{0, nil}` rather than making an extra request to count rows.
- **When a guess could destroy data, be explicit.** `delete_all` requires an
  `:interval`, and `:all` has to be spelled out.
- **The schema is the source of truth.**
  - Supervisor, task and compaction `dataSchema`s are generated from
    `Ecto.Druid.Schema`. Lookup factories are generated from
    `Ecto.Druid.Lookup`.
  - A dimension that reads an input field with a different name uses
    `from:`, which generates the transform.
  - Drift between the schema and a template raises.
- **Configuration comes from the repo config, not from environment
  directories.**
  - Templates are EEx files that take `assigns` from the repo config, set per
    environment in `runtime.exs`. The library itself has no notion of an
    environment.
  - Auth (`:auth`, `:redirect_trusted`) is set in the repo config and reaches
    every module. Each module and each call can override it.
  - Backfill templates live in their own directory and inherit the `:tasks`
    config.
- **Breaking changes are acceptable before 1.0 if they're documented.** See
  the conventions below.

## Druid behaviour to know

These were all verified against Druid 38 while building the library.

**Which service handles what**

- The Broker can't serve the supervisor, task, compaction, retention and
  lookup APIs. They're on the Router, Overlord or Coordinator, which is why
  each template module has its own host and port config.
- Broker and Historical `readiness` and `load_status` must be called directly.
  The Router doesn't forward them.
- A `:tasks` host may be an Overlord, and an Overlord doesn't serve SQL. Make
  Broker checks with the repo's own host.
- Compaction configs go through the Overlord API. With
  `useSupervisors: true`, the default in 38, posting a config creates an
  `autocompact__<ds>` supervisor.
- Marking segments used or unused also goes through the Overlord. The
  Coordinator paths for it are deprecated.

**Responses**

- Complex values come back from SQL as JSON-encoded Base64 strings.
  `DS_HISTOGRAM`, `DS_CDF` and `DS_GET_QUANTILES` come back as JSON strings of
  arrays.
- Native queries return sketches already decoded, times as epoch millis and
  booleans as `1`/`0`.
- Error bodies have three shapes:
  - `druidException`, with `errorCode`, `category` and `errorMessage`
  - the legacy shape, with `error`, `errorMessage` and `errorClass`
  - task submits, which return only `{"error": ...}`
- Some plain-text bodies are labelled JSON.
- An `arrayLines` result ends with a blank trailer line. If the trailer is
  missing, the result was truncated.

**Types and parameters**

- Druid has no boolean column type. Booleans are stored as LONG `1`/`0`, and
  sys-table flags are BIGINT.
- Parameters are positional `?` only. Pinned integers are sent as `BIGINT`,
  because Druid 38 rejects `LONG`. Decimals must be sent as JSON numbers,
  because Jason encodes them as strings.
- Some `sys.segments` start and end values can't be represented as an Elixir
  `DateTime`, so those fields are strings.

**SQL**

- Inside string literals, only `'` is escaped (by doubling it). Backslash is
  not an escape.
- Use `JSON_VALUE` with `$['a']` paths. There is no `json_extract`.
- `= ANY(...)` can't be planned. Use `SCALAR_IN_ARRAY`.
- Write weeks as `INTERVAL '7' DAY`, because a multiplied `INTERVAL '1' WEEK`
  is wrong.
- The only null orderings accepted are `ASC NULLS FIRST` and
  `DESC NULLS LAST`.
- A plain scan, which includes a lookup table, can't `ORDER BY` a non-time
  column.
- `nth_value` and MySQL cast types aren't supported.

**SQL ingestion**

- `INSERT` rejects a target column list. Select from `VALUES` with column
  aliases instead.
- `OVERWRITE WHERE` accepts only a `__time` range aligned to `PARTITIONED BY`.
  To delete or update rows, rewrite the whole interval with only the rows to
  keep.
- When negating a condition, use `IS NOT TRUE`, not `NOT`. `NOT` silently
  drops rows where the condition is NULL.
- There is no `SELECT * EXCLUDE`, so a rewrite must list every column.
- A batch task's interval widens to whole segments.
- A new column is "not found" until the Broker's schema refreshes.

**Timing and cancellation**

- A lookup update applies only if its version sorts higher as a string.
- Each deep-storage query runs as a task and takes about 7–8 seconds, even
  `SELECT 1`. Its statement id is `"query-" <> sqlQueryId`.
- A SQL cancel returns 404 until the Broker has registered the query, so it is
  retried.
- A cancel must not reuse the `receive_timeout` that has already expired.
- Req retries only GET and HEAD by default, so a POST poll needs explicit
  retry options. Health checks turn retries off so that they fail fast.

**Spec sync**

- Druid normalises the specs it stores. For example, `PT30M` comes back as
  `PT1800S`.
  - Supervisor sync leaves the decision to Druid with
    `skipRestartIfUnmodified`, instead of diffing on the client side.
  - Compaction sync compares only the keys in the template, so removing a
    setting needs `--force`.
- Retention rules that name a tier with no Historicals are accepted, and then
  unload the data. That is why sync refuses unknown tiers.

**Filter versions**

- The `equals`, `range` and `null` filters arrived in Druid 27, and the
  planner uses them by default from 28. The typed `in` filter arrived in 30.
- `selector` and `bound` aren't deprecated.

## Conventions

- Record every user-facing change in `CHANGELOG.md`, under the Unreleased
  section. Put breaking changes, with before and after examples, in
  `guides/upgrading.md`.
- The README is a short introduction that links to the guides. Usage detail
  belongs in `guides/`.
  - A new guide must be listed under `docs: [extras: ...]` in `mix.exs`.
  - A new public module must be added to a `groups_for_modules` group.
  - `mix docs --warnings-as-errors` must stay clean.
- Formatter: `.formatter.exs` exports `locals_without_parens` for the schema
  DSL. If you add a DSL macro, add it there too.
- PRs target `main`, with one focused change each. Describe what changed and
  why. Call out breaking changes and anything a reviewer should check.
  Before starting new work, update from `main`, since earlier PRs may have
  merged.
