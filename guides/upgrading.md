# Upgrading

## From 0.5.x to 0.6.0

### Druid and Ecto versions

0.6.0 targets and is tested against Apache Druid 38.0.0, up from 28. It isn't
tested against older versions, and some of what's new needs a newer Druid:

- A value `in` an array column compiles to
  `SCALAR_IN_ARRAY`, which Druid added in version 30. In 0.5 it compiled to
  `= ANY(...)`, which Druid can't plan.
- The native filter builders `Ecto.Druid.Native.Filter.equals/3`, `range/2`
  and `null/1` emit filter types that Druid added in version 27.

```elixir
from e in "events", where: "a" in e.tags

# 0.5: ... WHERE 'a' = ANY(e0."tags")
# 0.6: ... WHERE SCALAR_IN_ARRAY('a', e0."tags")
```

Ecto 3.12 or later is required (`ecto_sql ~> 3.12`).

### SQL function imports

The SQL function macros moved from `Ecto.Druid.Query` into per-category
submodules (`Ecto.Druid.Query.Numeric`, `Ecto.Druid.Query.DateTime`, and so
on). Replace `import Ecto.Druid.Query` with `use Ecto.Druid.Query` to bring
them all in (this also handles the `import Kernel, except: [...]` clause for
you), or import the individual submodules you need.

```elixir
# 0.5
import Ecto.Druid.Query

# 0.6
use Ecto.Druid.Query
# or
import Ecto.Druid.Query.DateTime, only: [time_floor: 2]
```

### Sketch results and parameters

`hll_sketch_estimate_with_error_bounds` now loads as an `Ecto.Druid.Estimate`
struct instead of a `[estimate, lower, upper]` list, and
`theta_sketch_estimate_with_error_bounds` as the same struct instead of a JSON
string. Read `value`, `lower_bound` and `upper_bound` from it.

```elixir
# 0.5
[estimate, lower, upper] = Repo.one(query)

# 0.6
%Ecto.Druid.Estimate{value: estimate, lower_bound: lower, upper_bound: upper} =
  Repo.one(query)
```

`tdigest_generate_sketch` now loads as a Base64 string, like the other
sketches, through the new `Ecto.Druid.TDigestSketch` type. In 0.5 it had no
type and loaded still JSON-encoded, wrapped in quotes. Remove any
`Jason.decode!/1` you added to unwrap it.

```elixir
# 0.5
"\"AAAAAT/wAAAAAAAA...\"" = Repo.one(query)

# 0.6
"AAAAAT/wAAAAAAAA..." = Repo.one(query)
```

The sketch types (`HLLSketch`, `ThetaSketch`, `QuantilesSketch`,
`TupleSketch` and `TDigestSketch`) now cast and dump Base64 strings:

- `cast/1` returns `{:ok, base64}` or `:error`. In 0.5 it returned the bare
  value, which broke `Ecto.Changeset.cast/4` and `type(^sketch, HLLSketch)`.
- A pinned sketch is sent as the Base64 string. In 0.5 it was JSON-encoded,
  wrapped in quotes, so drop any workaround for that. Decode it in the query
  with `decode_base64_complex/2` to use it as a sketch.

```elixir
from p in "page_views",
  select: theta_sketch_estimate(decode_base64_complex("thetaSketch", ^sessions))
```

### Native queries

`native_query/2` returns `{:ok, rows}` or
`{:error, %Ecto.Adapters.Druid.NativeQueryError{}}` instead of Druid's decoded
response, and flattens timeseries, topN, groupBy, scan and windowOperator
results into one map per row. `native_query!/2` returns the rows or raises.
`native_query!(query, raw: true)` returns Druid's decoded response, as
`native_query/2` did in 0.5.

```elixir
# 0.5: Druid's decoded response, or a raise
[%{"timestamp" => _, "result" => _} | _] = Repo.native_query(query)

# 0.6
{:ok, rows} = Repo.native_query(query)
rows = Repo.native_query!(query)
# Druid's decoded response, as in 0.5
[%{"timestamp" => _, "result" => _} | _] = Repo.native_query!(query, raw: true)
```

### Finch pool

Each repo now starts its own Finch pool, named `MyApp.Repo.Finch` (or the
repo's `:finch` option), instead of `Ecto.Adapters.Druid.Finch`. Update any
code that refers to the old name.

```elixir
# 0.5
Finch.build(:get, url) |> Finch.request(Ecto.Adapters.Druid.Finch)

# 0.6
Finch.build(:get, url) |> Finch.request(MyApp.Repo.Finch)
```
