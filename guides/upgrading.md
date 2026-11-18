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
