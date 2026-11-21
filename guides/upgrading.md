# Upgrading

## From 0.5.x to 0.6.0

The SQL function macros moved from `Ecto.Druid.Query` into per-category
submodules (`Ecto.Druid.Query.Numeric`, `Ecto.Druid.Query.DateTime`, and so
on). Replace `import Ecto.Druid.Query` with `use Ecto.Druid.Query` to bring
them all in (this also handles the `import Kernel, except: [...]` clause for
you), or import the individual submodules you need.

`hll_sketch_estimate_with_error_bounds` now loads as an `Ecto.Druid.Estimate`
struct instead of a `[estimate, lower, upper]` list, and
`theta_sketch_estimate_with_error_bounds` as the same struct instead of a JSON
string. Read `value`, `lower_bound` and `upper_bound` from it.

`native_query/2` returns `{:ok, rows}` or
`{:error, %Ecto.Adapters.Druid.NativeQueryError{}}` instead of Druid's decoded
response, and flattens timeseries, topN, groupBy, scan and windowOperator
results into one map per row. `native_query!/2` returns the rows or raises.
`native_query!(query, raw: true)` returns Druid's decoded response, as
`native_query/2` did in 0.5.

Each repo now starts its own Finch pool, named `MyApp.Repo.Finch` (or the
repo's `:finch` option), instead of `Ecto.Adapters.Druid.Finch`. Update any
code that refers to the old name.

Ecto 3.12 or later is required.
