defmodule Ecto.Druid.Query do
  import Ecto.Druid.Util, only: [sql_function: 1]

  sql_function table(source)
  sql_function extern(input_source, input_format, row_signature)
  sql_function approx_count_distinct_ds_theta(column, sketch_size)
  sql_function ds_quantiles_sketch(column, sketch_size)
  sql_function ds_histogram(column, split_points)
end
