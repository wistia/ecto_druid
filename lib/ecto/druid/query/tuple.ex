defmodule Ecto.Druid.Query.Tuple do
  @moduledoc """
  Druid [Tuple sketch functions and aggregations](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-tuple).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @doc "Computes approximate sums of the values contained within a Tuple sketch column which contains an array of double values as its Summary Object."
  sql_function ds_tuple_doubles_metrics_sum_estimate(expr)

  @doc "Returns an intersection of tuple sketches, where each input expression must return a tuple sketch which contains an array of double values as its Summary Object. The values contained in the Summary Objects are summed when combined. If the last value of the array is a numeric literal, Druid assumes that the value is an override parameter for nominal entries."
  sql_function ds_tuple_doubles_intersect(exprs), type: Ecto.Druid.TupleSketch

  @doc "Returns an intersection of tuple sketches, where each input expression must return a tuple sketch which contains an array of double values as its Summary Object. The values contained in the Summary Objects are summed when combined. If the last value of the array is a numeric literal, Druid assumes that the value is an override parameter for nominal entries."
  sql_function ds_tuple_doubles_intersect(exprs, nominal_entries), type: Ecto.Druid.TupleSketch

  @doc "Returns a set difference of tuple sketches, where each input expression must return a tuple sketch which contains an array of double values as its Summary Object. The values contained in the Summary Object are preserved as is. If the last value of the array is a numeric literal, Druid assumes that the value is an override parameter for nominal entries."
  sql_function ds_tuple_doubles_not(exprs), type: Ecto.Druid.TupleSketch

  @doc "Returns a set difference of tuple sketches, where each input expression must return a tuple sketch which contains an array of double values as its Summary Object. The values contained in the Summary Object are preserved as is. If the last value of the array is a numeric literal, Druid assumes that the value is an override parameter for nominal entries."
  sql_function ds_tuple_doubles_not(exprs, nominal_entries), type: Ecto.Druid.TupleSketch

  @doc "Returns a union of tuple sketches, where each input expression must return a tuple sketch which contains an array of double values as its Summary Object. The values contained in the Summary Objects are summed when combined. If the last value of the array is a numeric literal, Druid assumes that the value is an override parameter for nominal entries."
  sql_function ds_tuple_doubles_union(exprs), type: Ecto.Druid.TupleSketch

  @doc "Returns a union of tuple sketches, where each input expression must return a tuple sketch which contains an array of double values as its Summary Object. The values contained in the Summary Objects are summed when combined. If the last value of the array is a numeric literal, Druid assumes that the value is an override parameter for nominal entries."
  sql_function ds_tuple_doubles_union(exprs, nominal_entries), type: Ecto.Druid.TupleSketch

  @doc "Creates a Tuple sketch on the values of expr, which can be a regular column or a column containing tuple sketches. The k parameter is described in the Tuple sketch documentation."
  sql_function ds_tuple_doubles(expr), type: Ecto.Druid.TupleSketch

  @doc "Creates a Tuple sketch on the values of expr, which can be a regular column or a column containing tuple sketches. The k parameter is described in the Tuple sketch documentation."
  sql_function ds_tuple_doubles(expr, nominal_entries), type: Ecto.Druid.TupleSketch
end
