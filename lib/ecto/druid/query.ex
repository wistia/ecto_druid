defmodule Ecto.Druid.Query do
  @moduledoc """
  Entry point for Druid SQL function macros.

  The macros are organized into submodules mirroring the categories in the
  [Druid SQL documentation](https://druid.apache.org/docs/latest/querying/sql-functions):

  * `Ecto.Druid.Query.Numeric` - numeric scalar functions
  * `Ecto.Druid.Query.String` - string scalar functions
  * `Ecto.Druid.Query.DateTime` - date and time functions
  * `Ecto.Druid.Query.Reduction` - reduction functions (GREATEST/LEAST)
  * `Ecto.Druid.Query.IP` - IP address functions
  * `Ecto.Druid.Query.Scalar` - keyword-like and other scalar functions
  * `Ecto.Druid.Query.Aggregations` - general aggregation functions
  * `Ecto.Druid.Query.HLL` - HLL sketch functions and aggregations
  * `Ecto.Druid.Query.Theta` - Theta sketch functions and aggregations
  * `Ecto.Druid.Query.Quantiles` - Quantiles sketch functions and aggregations
  * `Ecto.Druid.Query.Tuple` - Tuple sketch functions and aggregations
  * `Ecto.Druid.Query.TDigest` - T-Digest sketch aggregations
  * `Ecto.Druid.Query.FixedBucketsHistogram` - fixed buckets histogram functions and aggregations
  * `Ecto.Druid.Query.Array` - array functions
  * `Ecto.Druid.Query.MultiValue` - multi-value string functions
  * `Ecto.Druid.Query.JSON` - JSON functions
  * `Ecto.Druid.Query.Table` - table functions (TABLE, EXTERN, EXTEND, APPEND, UNNEST)

  `use Ecto.Druid.Query` imports all of them, along with `import Kernel,
  except: [...]` for the handful of names that clash with `Kernel` (`abs`,
  `ceil`, `floor`, `div`, `length`, `trunc`, `round`):

      import Ecto.Query
      use Ecto.Druid.Query

      from(t in "test", select: time_floor(t.__time, "PT1H"))

  To pull in only one category, import its submodule directly:

      import Ecto.Druid.Query.DateTime, only: [time_floor: 2]

  > #### Migrating from `import Ecto.Druid.Query` {: .warning}
  >
  > Before version 0.6.0 every macro lived in this module and was brought in
  > with `import Ecto.Druid.Query`. Replace that line with
  > `use Ecto.Druid.Query` (and drop any manual `import Kernel, except: [...]`
  > you added alongside it).

  ## Window functions

  Druid window functions (`ROW_NUMBER`, `RANK`, `DENSE_RANK`, `PERCENT_RANK`,
  `CUME_DIST`, `NTILE`, `LAG`, `LEAD`, `FIRST_VALUE`, `LAST_VALUE`) need no
  macros from this library: use Ecto's built-in `Ecto.Query.WindowAPI` with
  `over/2` and `windows`:

      from(t in "test",
        select: over(row_number(), partition_by: t.page, order_by: t.added)
      )

  The exception is `nth_value/2`, which Ecto defines but Druid does not
  support; the adapter raises if it is used.
  """

  @submodules [
    Ecto.Druid.Query.Numeric,
    Ecto.Druid.Query.String,
    Ecto.Druid.Query.DateTime,
    Ecto.Druid.Query.Reduction,
    Ecto.Druid.Query.IP,
    Ecto.Druid.Query.Scalar,
    Ecto.Druid.Query.Aggregations,
    Ecto.Druid.Query.HLL,
    Ecto.Druid.Query.Theta,
    Ecto.Druid.Query.Quantiles,
    Ecto.Druid.Query.Tuple,
    Ecto.Druid.Query.TDigest,
    Ecto.Druid.Query.FixedBucketsHistogram,
    Ecto.Druid.Query.Array,
    Ecto.Druid.Query.MultiValue,
    Ecto.Druid.Query.JSON,
    Ecto.Druid.Query.Table
  ]

  @doc false
  def __submodules__, do: @submodules

  defmacro __using__(_opts) do
    imports =
      for mod <- @submodules do
        quote do
          import unquote(mod)
        end
      end

    quote do
      import Kernel,
        except: [abs: 1, ceil: 1, floor: 1, div: 2, length: 1, trunc: 1, round: 1]

      unquote_splicing(imports)
    end
  end
end
