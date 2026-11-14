defmodule Ecto.Druid.Query.Scalar do
  @moduledoc """
  Druid keyword-like and [other scalar functions](https://druid.apache.org/docs/latest/querying/sql-scalar#other-scalar-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @time_unit ~w(SECOND MINUTE HOUR DAY WEEK MONTH QUARTER YEAR)
  @doc "Applies DISTINCT modifier to expr."
  sql_function distinct(expr), wrapper: {" ", ""}

  defmacro interval(value, unit) when unit in @time_unit do
    Ecto.Druid.Util.sql_function_body(
      "INTERVAL",
      "? #{unit}",
      [value],
      nil,
      {" ", ""}
    )
  end

  @doc "Returns true if the value of expr is contained in the base64-serialized Bloom filter. See the Bloom filter extension documentation for additional details. See the BLOOM_FILTER function for computing Bloom filters."
  sql_function bloom_filter_test(expr, serialized_filter)

  @doc "Simple CASE."
  defmacro sql_case(expr, clauses) do
    placeholders =
      clauses
      |> Keyword.keys()
      |> Enum.map(fn keyword ->
        keyword
        |> to_string()
        |> String.upcase()
        |> Kernel.<>(" ? ")
      end)

    args = Keyword.values(clauses)

    Ecto.Druid.Util.sql_function_body("CASE", placeholders, [expr | args], nil, {" ? ", "END"})
  end

  @doc "Searched CASE."
  defmacro sql_case(clauses) do
    placeholders =
      clauses
      |> Keyword.keys()
      |> Enum.map(fn keyword ->
        keyword
        |> to_string()
        |> String.upcase()
        |> Kernel.<>(" ? ")
      end)

    args = Keyword.values(clauses)

    Ecto.Druid.Util.sql_function_body("CASE", placeholders, args, nil, {" ", "END"})
  end

  @doc "Returns the first value that is neither NULL nor empty string."
  sql_function coalesce(exprs)

  @doc """
  Decodes a Base64-encoded string into a complex data type, where dataType is the complex data type and expr is the Base64-encoded string to decode. The hyperUnique and serializablePairLongString data types are supported by default. You can enable support for the following complex data types by loading their extensions: druid-bloom-filter: bloom druid-datasketches: arrayOfDoublesSketch, HLLSketch, KllDoublesSketch, KllFloatsSketch, quantilesDoublesSketch, thetaSketch druid-histogram: approximateHistogram, fixedBucketsHistogram druid-stats: variance druid-compressed-big-decimal: compressedBigDecimal druid-momentsketch: momentSketch druid-tdigestsketch: tDigestSketch

    druid-bloom-filter: bloom
    druid-datasketches: arrayOfDoublesSketch, HLLSketch, KllDoublesSketch, KllFloatsSketch, quantilesDoublesSketch, thetaSketch
    druid-histogram: approximateHistogram, fixedBucketsHistogram
    druid-stats: variance
    druid-compressed-big-decimal: compressedBigDecimal
    druid-momentsketch: momentSketch
    druid-tdigestsketch: tDigestSketch

  """
  sql_function decode_base64_complex(data_type, expr)

  @doc "Returns NULL if value1 and value2 match, else returns value1."
  sql_function nullif(value1, value2)

  @doc "Returns value1 if value1 is not null, otherwise value2."
  sql_function nvl(value1, value2)
end
