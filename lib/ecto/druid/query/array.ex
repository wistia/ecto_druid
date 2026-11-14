defmodule Ecto.Druid.Query.Array do
  @moduledoc """
  Druid [array functions](https://druid.apache.org/docs/latest/querying/sql-array-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @doc "Constructs a SQL ARRAY literal from the expression arguments, using the type of the first argument as the output array type."
  sql_function array(exprs), wrapper: {"[", "]"}

  @doc "Returns length of the array expression."
  sql_function array_length(arr)

  @doc "Returns the array element at the 0-based index supplied, or null for an out of range index."
  sql_function array_offset(arr, long)

  @doc "Returns the array element at the 1-based index supplied, or null for an out of range index."
  sql_function array_ordinal(arr, long)

  @doc "If expr is a scalar type, returns 1 if arr contains expr. If expr is an array, returns 1 if arr contains all elements of expr. Otherwise returns 0."
  sql_function array_contains(arr, expr)

  @doc "Returns 1 if arr1 and arr2 have any elements in common, else 0."
  sql_function array_overlap(arr1, arr2)

  @doc "Returns the 0-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null."
  sql_function array_offset_of(arr, expr)

  @doc "Returns the 1-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null."
  sql_function array_ordinal_of(arr, expr)

  @doc "Adds expr to the beginning of arr, the resulting array type determined by the type of arr."
  sql_function array_prepend(expr, arr)

  @doc "Appends expr to arr, the resulting array type determined by the type of arr."
  sql_function array_append(arr, expr)

  @doc "Concatenates arr2 to arr1. The resulting array type is determined by the type of arr1."
  sql_function array_concat(arr1, arr2)

  @doc "Returns the subarray of arr from the 0-based index start (inclusive) to end (exclusive). Returns null, if start is less than 0, greater than length of arr, or greater than end."
  sql_function array_slice(arr, start, stop)

  @doc "Joins all elements of arr by the delimiter specified by str."
  sql_function array_to_string(arr, str)

  @doc "Splits str1 into an array on the delimiter specified by str2, which is a regular expression."
  sql_function string_to_array(str1, str2)

  @doc "Converts an ARRAY of any type into a multi-value string VARCHAR."
  sql_function array_to_mv(arr)

  @doc "Returns true if the scalar value of expr is present in arr. Returns false if it is non-null and not present. Returns UNKNOWN (null) if either expr is null, or if expr is non-null but not present in a null arr."
  sql_function scalar_in_array(expr, arr)
end
