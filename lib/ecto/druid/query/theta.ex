defmodule Ecto.Druid.Query.Theta do
  @moduledoc """
  Druid [Theta sketch functions and aggregations](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-theta).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]
  @doc "Returns the distinct count estimate from a theta sketch. expr must return a theta sketch."
  sql_function theta_sketch_estimate(expr)

  @doc "Returns the distinct count estimate and error bounds from a theta sketch. expr must return a theta sketch."
  sql_function theta_sketch_estimate_with_error_bounds(expr, error_bounds_std_dev)

  @doc "Returns a union of theta sketches, where each input expression must return a theta sketch. The size can be optionally specified as the first parameter."
  sql_function theta_sketch_union(exprs), type: Ecto.Druid.ThetaSketch

  @doc "Returns a union of theta sketches, where each input expression must return a theta sketch. The size can be optionally specified as the first parameter."
  sql_function theta_sketch_union(size, exprs), type: Ecto.Druid.ThetaSketch

  @doc "Returns an intersection of theta sketches, where each input expression must return a theta sketch. The size can be optionally specified as the first parameter."
  sql_function theta_sketch_intersect(exprs), type: Ecto.Druid.ThetaSketch

  @doc "Returns an intersection of theta sketches, where each input expression must return a theta sketch. The size can be optionally specified as the first parameter."
  sql_function theta_sketch_intersect(size, exprs), type: Ecto.Druid.ThetaSketch

  @doc "Returns a set difference of theta sketches, where each input expression must return a theta sketch. The size can be optionally specified as the first parameter."
  sql_function theta_sketch_not(exprs), type: Ecto.Druid.ThetaSketch

  @doc "Returns a set difference of theta sketches, where each input expression must return a theta sketch. The size can be optionally specified as the first parameter."
  sql_function theta_sketch_not(size, exprs), type: Ecto.Druid.ThetaSketch

  @doc "Counts distinct values of expr, which can be a regular column or a Theta sketch column. Results are always approximate, regardless of the value of useApproximateCountDistinct. The size parameter is described in the Theta sketch documentation. See also COUNT(DISTINCT expr)."
  sql_function approx_count_distinct_ds_theta(column)

  @doc "Counts distinct values of expr, which can be a regular column or a Theta sketch column. Results are always approximate, regardless of the value of useApproximateCountDistinct. The size parameter is described in the Theta sketch documentation. See also COUNT(DISTINCT expr)."
  sql_function approx_count_distinct_ds_theta(column, sketch_size)

  @doc "Creates a Theta sketch on the values of expr, which can be a regular column or a column containing Theta sketches. The size parameter is described in the Theta sketch documentation."
  sql_function ds_theta(column), type: Ecto.Druid.ThetaSketch

  @doc "Creates a Theta sketch on the values of expr, which can be a regular column or a column containing Theta sketches. The size parameter is described in the Theta sketch documentation."
  sql_function ds_theta(column, sketch_size), type: Ecto.Druid.ThetaSketch
end
