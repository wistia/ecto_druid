defmodule Ecto.Druid.Query.FixedBucketsHistogram do
  @moduledoc """
  Druid [fixed buckets histogram](https://druid.apache.org/docs/latest/development/extensions-core/approximate-histograms#fixed-buckets-histogram)
  functions and aggregations, from the `druid-histogram` extension.

  `fixed_buckets_histogram` builds a histogram from a numeric column or merges
  a column of prebuilt `fixedBucketsHistogram` values. The other functions read
  a histogram, much as the `DS_*` functions in `Ecto.Druid.Query.Quantiles`
  read a quantiles sketch:

      from p in "page_views",
        select: %{
          depth: fixed_buckets_histogram(p.scroll_depth, 100, 0, 100),
          median:
            fixed_buckets_histogram_quantile(
              fixed_buckets_histogram(p.scroll_depth, 100, 0, 100),
              0.5
            )
        }
      #=> %{depth: "AQEAAAA...", median: 51.0}

  The functions that read a histogram need one built in the same query, or a
  subquery column that holds one. To read a stored histogram column, merge it
  with `fixed_buckets_histogram` first. The bucket count, the limits and the
  outlier handling mode, and the probability passed to
  `fixed_buckets_histogram_quantile`, must be literals, not pinned values.

  `approx_quantile_fixed_buckets` in `Ecto.Druid.Query.Aggregations` computes
  a single quantile in one step.
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @doc "Builds a fixed buckets histogram from the values of expr, which can be a numeric column or a column of fixed buckets histograms. num_buckets buckets of equal width cover lower_limit to upper_limit. Values outside the limits are ignored; use the five-argument form to count or clip them instead."
  sql_function fixed_buckets_histogram(expr, num_buckets, lower_limit, upper_limit),
    type: Ecto.Druid.FixedBucketsHistogram

  @doc "Builds a fixed buckets histogram from the values of expr, which can be a numeric column or a column of fixed buckets histograms. num_buckets buckets of equal width cover lower_limit to upper_limit. outlier_handling_mode is `'ignore'` (the default), `'overflow'` or `'clip'`, as described in the fixed buckets histogram documentation."
  sql_function fixed_buckets_histogram(
                 expr,
                 num_buckets,
                 lower_limit,
                 upper_limit,
                 outlier_handling_mode
               ),
               type: Ecto.Druid.FixedBucketsHistogram

  @doc "Returns the quantile estimate corresponding to fraction, between 0 and 1, from a fixed buckets histogram. expr must be a fixed_buckets_histogram aggregation or a subquery column holding one."
  sql_function fixed_buckets_histogram_quantile(expr, fraction)

  @doc "Returns the minimum value seen by a fixed buckets histogram. expr must be a fixed_buckets_histogram aggregation or a subquery column holding one."
  sql_function fixed_buckets_histogram_min(expr)

  @doc "Returns the maximum value seen by a fixed buckets histogram. expr must be a fixed_buckets_histogram aggregation or a subquery column holding one."
  sql_function fixed_buckets_histogram_max(expr)
end
