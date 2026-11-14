defmodule Ecto.Druid.Query.HLL do
  @moduledoc """
  Druid [HLL sketch functions and aggregations](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-hll).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @doc "Returns the distinct count estimate from an HLL sketch. expr must return an HLL sketch. The optional round boolean parameter will round the estimate if set to true, with a default of false."
  sql_function hll_sketch_estimate(expr)

  @doc "Returns the distinct count estimate from an HLL sketch. expr must return an HLL sketch. The optional round boolean parameter will round the estimate if set to true, with a default of false."
  sql_function hll_sketch_estimate(expr, round)

  @doc "Returns the distinct count estimate and error bounds from an HLL sketch. expr must return an HLL sketch. An optional numStdDev argument can be provided."
  sql_function hll_sketch_estimate_with_error_bounds(expr)

  @doc "Returns the distinct count estimate and error bounds from an HLL sketch. expr must return an HLL sketch. An optional numStdDev argument can be provided."
  sql_function hll_sketch_estimate_with_error_bounds(expr, num_std_dev)

  @doc "Returns a union of HLL sketches, where each input expression must return an HLL sketch. The lgK and tgtHllType can be optionally specified as the first parameter; if provided, both optional parameters must be specified."
  sql_function hll_sketch_union(exprs), type: Ecto.Druid.HLLSketch

  @doc "Returns a union of HLL sketches, where each input expression must return an HLL sketch. The lgK and tgtHllType can be optionally specified as the first parameter; if provided, both optional parameters must be specified."
  sql_function hll_sketch_union(lg_k, tgt_hll_type, exprs), type: Ecto.Druid.HLLSketch

  @doc "Returns a human-readable string representation of an HLL sketch for debugging. expr must return an HLL sketch."
  sql_function hll_sketch_to_string(expr)

  @doc "Counts distinct values of expr, which can be a regular column or an HLL sketch column. Results are always approximate, regardless of the value of useApproximateCountDistinct. The lgK and tgtHllType parameters are described in the HLL sketch documentation. See also COUNT(DISTINCT expr)."
  sql_function approx_count_distinct_ds_hll(expr)

  @doc "Counts distinct values of expr, which can be a regular column or an HLL sketch column. Results are always approximate, regardless of the value of useApproximateCountDistinct. The lgK and tgtHllType parameters are described in the HLL sketch documentation. See also COUNT(DISTINCT expr)."
  sql_function approx_count_distinct_ds_hll(expr, lg_k)

  @doc "Counts distinct values of expr, which can be a regular column or an HLL sketch column. Results are always approximate, regardless of the value of useApproximateCountDistinct. The lgK and tgtHllType parameters are described in the HLL sketch documentation. See also COUNT(DISTINCT expr)."
  sql_function approx_count_distinct_ds_hll(expr, lg_k, tgt_hll_type)

  @doc "Creates an HLL sketch on the values of expr, which can be a regular column or a column containing HLL sketches. The lgK and tgtHllType parameters are described in the HLL sketch documentation."
  sql_function ds_hll(expr), type: Ecto.Druid.HLLSketch

  @doc "Creates an HLL sketch on the values of expr, which can be a regular column or a column containing HLL sketches. The lgK and tgtHllType parameters are described in the HLL sketch documentation."
  sql_function ds_hll(expr, lg_k), type: Ecto.Druid.HLLSketch

  @doc "Creates an HLL sketch on the values of expr, which can be a regular column or a column containing HLL sketches. The lgK and tgtHllType parameters are described in the HLL sketch documentation."
  sql_function ds_hll(expr, lg_k, tgt_hll_type), type: Ecto.Druid.HLLSketch
end
