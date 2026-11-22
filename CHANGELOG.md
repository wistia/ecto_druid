# Changelog

## Unreleased

### Breaking changes

- SQL function macros whose names clash with `Kernel` or a special form now
  end in `_`: `abs_`, `ceil_`, `floor_`, `div_`, `length_`, `trunc_`,
  `round_` and `case_` (was `sql_case`). `use Ecto.Druid.Query` no longer
  excludes anything from `Kernel`, so `length/1`, `round/1` and the rest keep
  working in modules that use it. See [Upgrading](guides/upgrading.md).

### Documentation

- `Druid.Client.Task.shutdown_all/1` documents that Druid 32 to 39 answer its
  request with a 404 even when the data source has active tasks
  ([apache/druid#18419](https://github.com/apache/druid/issues/18419)), and
  how to shut the tasks down one by one instead.
- The Testing guide explains why tests that query Druid don't need a case
  template of their own.
- The Testing guide's setup for stubbed and real-Druid tests makes
  `DRUID_TESTS` the only switch: `test/test_helper.exs` runs just the
  `:druid` tests when it's set, so `DRUID_TESTS=1 mix test` no longer sends
  the stubbed tests' queries to Druid. It replaces
  `DRUID_TESTS=1 mix test --only druid`.

## 0.6.0 (2026-11-21)

Targets Apache Druid 38 (up from 28). See [Upgrading](guides/upgrading.md)
for how to move code from 0.5.x.

### Breaking changes

- Requires Ecto 3.12 or later (`ecto_sql ~> 3.12`).
- The SQL function macros moved from `Ecto.Druid.Query` into per-category
  submodules (`Ecto.Druid.Query.Numeric`, `Ecto.Druid.Query.DateTime`, ...).
  `use Ecto.Druid.Query` imports them all; `import Ecto.Druid.Query` no longer
  does.
- `native_query/2` returns `{:ok, rows}` or `{:error, %NativeQueryError{}}`,
  and `native_query!/2` returns the rows or raises. Timeseries, topN, groupBy,
  scan and windowOperator results are flattened into rows; pass `raw: true`
  for Druid's response as is.
- `hll_sketch_estimate_with_error_bounds` and
  `theta_sketch_estimate_with_error_bounds` load as an `Ecto.Druid.Estimate`
  struct.
- Sketch types cast and dump Base64 strings, and load Druid's JSON-encoded
  form or a bare string. A pinned sketch is sent as the Base64 string rather
  than JSON-encoded. `tdigest_generate_sketch` loads as a Base64 string,
  through a new `Ecto.Druid.TDigestSketch` type, rather than JSON-encoded.
- Each repo starts its own Finch pool, named after the repo
  (`MyApp.Repo.Finch`) or the `:finch` option, instead of
  `Ecto.Adapters.Druid.Finch`.
- `insert/update/delete` raise errors that point at what to use instead.

### Added

- `projection/2` in `Ecto.Druid.Schema` declares Druid projections. They're
  included in `Ecto.Druid.Schema.Spec.data_schema/2`, and the `projections`
  template helper adds them to compaction configs.
- `Repo.insert_all/3` through Druid SQL-based ingestion, with `:overwrite`,
  `:partitioned_by` and `:clustered_by`.
- `Repo.delete_all/2` and `Repo.update_all/3`, which rewrite an `:interval`
  with SQL-based ingestion `REPLACE`: without the matching rows, or with
  their columns changed. `update_all` supports `set`, `inc`, `push` and (on
  multi-value columns) `pull`, and needs an `Ecto.Druid.Schema` to know every
  column. Both return `{0, nil}`.
- `extern/2` and `extend/2`, for reading external data with its columns
  declared in SQL (`TABLE(EXTERN(?, ?)) EXTEND (...)`) rather than as a JSON
  row signature. `extern/2,3` take maps and lists and encode them as JSON,
  and `extern/3` takes a keyword list of columns as its row signature.
- `Repo.stream/2`, and querying from deep storage.
- `Repo.to_native/2`, native query builders for filters, aggregators and
  expressions (`Ecto.Druid.Native`), and `Ecto.Druid.Native.rows/3` for
  flattening results. A schema can be a native query's `dataSource`, and the
  columns the query reads are checked against it.
- `unnest/2`, and SQL functions added in Druid 28 to 38:
  `APPROX_COUNT_DISTINCT_DS_HLL`, `DS_HLL`, `SCALAR_IN_ARRAY`,
  `MV_FILTER_REGEX`, `MV_FILTER_PREFIX` and `JSON_MERGE`.
- `Ecto.Druid.Interval` for building query intervals, and `{start, stop}`
  tuples in `time_in_interval/2`.
- Schemas for Druid's system tables (`sys.*` and `INFORMATION_SCHEMA.*`), and
  `Ecto.Druid.JSON` for their JSON columns.
- `Ecto.Druid.Lookup` for defining lookup schemas, which `lookup/2,3` accept
  in place of a lookup name.
- Template-and-sync workflows, each with Mix tasks: `Druid.Supervisors` for
  supervisor specs, `Druid.Retention` for retention rules, `Druid.Lookups`
  for lookups, `Druid.Compaction` for compaction configs, and `Druid.Tasks`
  for batch ingestion tasks and range backfills. `Ecto.Druid.Schema`
  generates a `dataSchema` from an Ecto schema.
- Helpers for waiting on Druid: `Druid.Tasks.await/3` and `await_all/3`
  (optionally until segments are queryable),
  `Druid.Supervisors.await_running/3` and `handoff/3`, and
  `Druid.Lookups.await/3`.
- Request builders for the rest of Druid's HTTP API in `Druid.Client`.
- Repo-config `:context` merged under the per-call `context:` option.
- `:auth` and `:redirect_trusted` options for authenticated clusters.
- Telemetry: the repo's `[..., :query]` event with query logging,
  `[:druid, :request]` spans for every client request, and
  `[:druid, :task, :await]` and `[:druid, :statement, :await]` spans.
- An example Phoenix LiveView app in `example/`.
- `Ecto.Druid.Test`, which stubs Druid in an app's tests through
  `Req.Test`. A stub gets each SQL, deep storage, ingestion or native query
  and returns its rows, and answers the way Druid does, including errors,
  timeouts and failed tasks. See the [Testing](guides/testing.md) guide.
  `:plug` is now an optional dependency.
- `Ecto.Druid.Fixtures.load!/3`, which loads test data into Druid once
  before a suite runs, replacing what's in each data source. Rows are
  ingested through an `Ecto.Druid.Schema`'s generated `dataSchema`.
- Guides on HexDocs, split out of the README.
- A Time zones section in the Querying guide.

### Fixed

- SQL queries and native queries are canceled in Druid when their request
  times out. Cancels are retried with backoff.
- SQL generated for Ecto's built-in expressions: `type/2` casts, string
  literals with backslashes, `datetime_add` and the other date arithmetic,
  JSON paths and `x in array_field`.
- `distinct: true` and top-level `ORDER BY` with Ecto 3.12's `ByExpr`.
- Pinned integers, `DateTime`s, `Date`s, `Decimal`s, `nil` and lists.
- Loading `:date`, `:utc_datetime` and `:naive_datetime` results.
- Pinned `DateTime`s with a non-UTC `sqlTimeZone`. Druid reads a timestamp
  parameter as a wall-clock time in that zone and ignores its offset, so they
  were off by the zone's offset. They're now sent as the wall-clock time in
  `sqlTimeZone`. Zones with daylight saving time need a time zone database.
- `:date` and `:naive_datetime` results with a `sqlTimeZone` are the date and
  wall-clock time in that zone, rather than in UTC. Dates were a day early in
  zones east of UTC.
- Sketch casts in changesets, arrays and pinned values.
- A second repo no longer crashes at boot over the shared Finch pool name.
- A repo's `:plug` config reaches `Druid.Tasks`, `Druid.Supervisors`,
  `Druid.Retention`, `Druid.Lookups` and `Druid.Compaction`, like its
  `:host` and `:auth`. `insert_all` waited for its task through them, so
  with a repo plug it submitted the task to the plug and then polled the
  real host.

### Removed

- The unused MySQL DDL generation.
