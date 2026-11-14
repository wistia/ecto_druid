defmodule Ecto.Druid.Query.MultiValue do
  @moduledoc """
  Druid [multi-value string functions](https://druid.apache.org/docs/latest/querying/sql-multivalue-string-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1]
  @doc "Filters multi-value expr to include only values contained in array arr."
  sql_function mv_filter_only(expr, arr)

  @doc "Filters multi-value expr to include no values contained in array arr."
  sql_function mv_filter_none(expr, arr)

  @doc "Returns length of the array expression."
  sql_function mv_length(arr)

  @doc "Returns the array element at the 0-based index supplied, or null for an out of range index."
  sql_function mv_offset(arr, long)

  @doc "Returns the array element at the 1-based index supplied, or null for an out of range index."
  sql_function mv_ordinal(arr, long)

  @doc "If expr is a scalar type, returns 1 if arr contains expr. If expr is an array, returns 1 if arr contains all elements of expr. Otherwise returns 0."
  sql_function mv_contains(arr, expr)

  @doc "Returns 1 if arr1 and arr2 have any elements in common, else 0."
  sql_function mv_overlap(arr1, arr2)

  @doc "Returns the 0-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null."
  sql_function mv_offset_of(arr, expr)

  @doc "Returns the 1-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null."
  sql_function mv_ordinal_of(arr, expr)

  @doc "Adds expr to the beginning of arr, the resulting array type determined by the type of arr."
  sql_function mv_prepend(expr, arr)

  @doc "Appends expr to arr, the resulting array type determined by the type of arr."
  sql_function mv_append(arr, expr)

  @doc "Concatenates arr2 to arr1. The resulting array type is determined by the type of arr1."
  sql_function mv_concat(arr1, arr2)

  @doc "Returns the subarray of arr from the 0-based index start(inclusive) to end(exclusive), or null, if start is less than 0, greater than length of arr or greater than end."
  sql_function mv_slice(arr, start, stop)

  @doc "Joins all elements of arr by the delimiter specified by str."
  sql_function mv_to_string(arr, str)

  @doc "Splits str1 into an array on the delimiter specified by str2, which is a regular expression."
  sql_function string_to_mv(str1, str2)

  @doc "Converts a multi-value string from a VARCHAR to a VARCHAR ARRAY."
  sql_function mv_to_array(str)

  @doc "Filters multi-value expr to include only values matching the regular expression pattern."
  sql_function mv_filter_regex(expr, pattern)

  @doc "Filters multi-value expr to include only values with the specified prefix."
  sql_function mv_filter_prefix(expr, prefix)
end
