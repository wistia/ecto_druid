defmodule Ecto.Druid.Query.Quantiles do
  @moduledoc """
  Druid [Quantiles sketch functions and aggregations](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-quantiles).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @doc "Returns the quantile estimate corresponding to fraction from a quantiles sketch. expr must return a quantiles sketch."
  sql_function ds_get_quantile(expr, fraction)

  @doc "Returns a string representing an array of quantile estimates corresponding to a list of fractions from a quantiles sketch. expr must return a quantiles sketch."
  sql_function ds_get_quantiles(expr, fractions), type: Ecto.Druid.DSHistogram

  @doc "Returns a string representing an approximation to the histogram given a list of split points that define the histogram bins from a quantiles sketch. expr must return a quantiles sketch."
  sql_function ds_histogram(expr, split_points), type: Ecto.Druid.DSHistogram

  @doc "Returns a string representing approximation to the Cumulative Distribution Function given a list of split points that define the edges of the bins from a quantiles sketch. expr must return a quantiles sketch."
  sql_function ds_cdf(expr, split_points), type: Ecto.Druid.DSHistogram

  @doc "Returns an approximation to the rank of a given value that is the fraction of the distribution less than that value from a quantiles sketch. expr must return a quantiles sketch."
  sql_function ds_rank(expr, value)

  @doc "Returns a string summary of a quantiles sketch, useful for debugging. expr must return a quantiles sketch."
  sql_function ds_quantile_summary(expr)

  @doc "Computes approximate quantiles on numeric or Quantiles sketch expressions. The probability value should be between 0 and 1, exclusive. The k parameter is described in the Quantiles sketch documentation."
  sql_function approx_quantile_ds(expr, probability)

  @doc "Computes approximate quantiles on numeric or Quantiles sketch expressions. The probability value should be between 0 and 1, exclusive. The k parameter is described in the Quantiles sketch documentation."
  sql_function approx_quantile_ds(expr, probability, sketch_size)

  @doc "Creates a Quantiles sketch on the values of expr, which can be a regular column or a column containing quantiles sketches. The k parameter is described in the Quantiles sketch documentation."
  sql_function ds_quantiles_sketch(expr), type: Ecto.Druid.QuantilesSketch

  @doc "Creates a Quantiles sketch on the values of expr, which can be a regular column or a column containing quantiles sketches. The k parameter is described in the Quantiles sketch documentation."
  sql_function ds_quantiles_sketch(expr, sketch_size), type: Ecto.Druid.QuantilesSketch
end
