defmodule Ecto.Druid.Query.Aggregations do
  @moduledoc """
  Druid general [aggregation functions](https://druid.apache.org/docs/latest/querying/sql-aggregations).
  """
  import Ecto.Druid.Util, only: [sql_function: 1]

  @doc """
  Counts distinct values of expr using an approximate algorithm. The expr can be a regular column or a prebuilt sketch column.

  The specific algorithm depends on the value of druid.sql.approxCountDistinct.function. By default, this is APPROX_COUNT_DISTINCT_BUILTIN. If the DataSketches extension is loaded, you can set it to APPROX_COUNT_DISTINCT_DS_HLL or APPROX_COUNT_DISTINCT_DS_THETA.

  When run on prebuilt sketch columns, the sketch column type must match the implementation of this function. For example: when druid.sql.approxCountDistinct.function is set to APPROX_COUNT_DISTINCT_BUILTIN, this function runs on prebuilt hyperUnique columns, but not on prebuilt HLLSketchBuild columns.
  """
  sql_function approx_count_distinct(expr)

  @doc """
  Usage note: consider using APPROX_COUNT_DISTINCT_DS_HLL instead, which offers better accuracy in many cases.
  Counts distinct values of expr using Druid's built-in "cardinality" or "hyperUnique" aggregators, which implement a variant of HyperLogLog. The expr can be a string, a number, or a prebuilt hyperUnique column. Results are always approximate, regardless of the value of useApproximateCountDistinct.
  """
  sql_function approx_count_distinct_builtin(expr)

  @doc """
  Deprecated. Use APPROX_QUANTILE_DS instead, which provides a superior distribution-independent algorithm with formal error guarantees.

  Computes approximate quantiles on numeric or approxHistogram expressions. probability should be between 0 and 1, exclusive. resolution is the number of centroids to use for the computation. Higher resolutions will give more precise results but also have higher overhead. If not provided, the default resolution is 50. Load the approximate histogram extension to use this function.
  """
  @deprecated "Use approx_quantile_ds/2 instead"
  sql_function approx_quantile(expr, probability)

  @doc """
  Deprecated. Use APPROX_QUANTILE_DS instead, which provides a superior distribution-independent algorithm with formal error guarantees.

  Computes approximate quantiles on numeric or approxHistogram expressions. probability should be between 0 and 1, exclusive. resolution is the number of centroids to use for the computation. Higher resolutions will give more precise results but also have higher overhead. If not provided, the default resolution is 50. Load the approximate histogram extension to use this function.
  """
  @deprecated "Use approx_quantile_ds/3 instead"
  sql_function approx_quantile(expr, probability, resolution)

  @doc "Computes approximate quantiles on numeric or fixed buckets histogram expressions. probability should be between 0 and 1, exclusive. The numBuckets, lowerLimit, upperLimit, and outlierHandlingMode parameters are described in the fixed buckets histogram documentation. Load the approximate histogram extension to use this function."
  sql_function approx_quantile_fixed_buckets(
                 expr,
                 probability,
                 num_buckets,
                 lower_limit,
                 upper_limit
               )

  @doc "Computes approximate quantiles on numeric or fixed buckets histogram expressions. probability should be between 0 and 1, exclusive. The numBuckets, lowerLimit, upperLimit, and outlierHandlingMode parameters are described in the fixed buckets histogram documentation. Load the approximate histogram extension to use this function."
  sql_function approx_quantile_fixed_buckets(
                 expr,
                 probability,
                 num_buckets,
                 lower_limit,
                 upper_limit,
                 outlier_handling_mode
               )

  @doc "Computes a bloom filter from values produced by expr, with numEntries maximum number of distinct values before false positive rate increases. See bloom filter extension documentation for additional details."
  sql_function bloom_filter(expr, num_entries)

  @doc "Computes variance population of expr. See stats extension documentation for additional details."
  sql_function var_pop(expr)

  @doc "Computes variance sample of expr. See stats extension documentation for additional details."
  sql_function var_samp(expr)

  @doc "Alias for VAR_SAMP. Computes the sample variance of expr. See stats extension documentation for additional details."
  sql_function variance(expr)

  @doc "Computes standard deviation population of expr. See stats extension documentation for additional details."
  sql_function stddev_pop(expr)

  @doc "Computes standard deviation sample of expr. See stats extension documentation for additional details."
  sql_function stddev_samp(expr)

  @doc "Alias for STDDEV_SAMP. Computes the sample standard deviation of expr. See stats extension documentation for additional details."
  sql_function stddev(expr)

  @doc """
  Returns the earliest value of expr.
  If expr comes from a relation with a timestamp column (like __time in a Druid datasource), the "earliest" is taken from the row with the overall earliest non-null value of the timestamp column.
  If the earliest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows. If expr does not come from a relation with a timestamp, then it is simply the first value encountered.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.
  """
  sql_function earliest(expr)

  @doc """
  Returns the earliest value of expr.
  If expr comes from a relation with a timestamp column (like __time in a Druid datasource), the "earliest" is taken from the row with the overall earliest non-null value of the timestamp column.
  If the earliest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows. If expr does not come from a relation with a timestamp, then it is simply the first value encountered.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.
  """
  sql_function earliest(expr, max_bytes_per_value)

  @doc """
  Returns the earliest value of expr.
  The earliest value of expr is taken from the row with the overall earliest non-null value of timestampExpr.
  If the earliest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use EARLIEST instead of EARLIEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.
  """
  sql_function earliest_by(expr, timestamp_expr)

  @doc """
  Returns the earliest value of expr.
  The earliest value of expr is taken from the row with the overall earliest non-null value of timestampExpr.
  If the overall earliest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use EARLIEST instead of EARLIEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.
  """
  sql_function earliest_by(expr, timestamp_expr, max_bytes_per_value)

  @doc """
  Returns the latest value of expr
  The expr must come from a relation with a timestamp column (like __time in a Druid datasource) and the "latest" is taken from the row with the overall latest non-null value of the timestamp column.
  If the latest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.
  """
  sql_function latest(expr)

  @doc """
  Returns the latest value of expr
  The expr must come from a relation with a timestamp column (like __time in a Druid datasource) and the "latest" is taken from the row with the overall latest non-null value of the timestamp column.
  If the latest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.
  """
  sql_function latest(expr, max_bytes_per_value)

  @doc """
  Returns the latest value of expr
  The latest value of expr is taken from the row with the overall latest non-null value of timestampExpr.
  If the overall latest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use LATEST instead of LATEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.
  """
  sql_function latest_by(expr, timestamp_expr)

  @doc """
  Returns the latest value of expr
  The latest value of expr is taken from the row with the overall latest non-null value of timestampExpr.
  If the overall latest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use LATEST instead of LATEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.
  """
  sql_function latest_by(expr, timestamp_expr, max_bytes_per_value)

  @doc """
  Returns any value of expr including null. This aggregator can simplify and optimize the performance by returning the first encountered value (including null).

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValue is omitted; it defaults to 1024. aggregateMultipleValues is an optional boolean flag controls the behavior of aggregating a multi-value dimension. aggregateMultipleValues is set as true by default and returns the stringified array in case of a multi-value dimension. By setting it to false, function will return first value instead.
  """
  sql_function any_value(expr)

  @doc """
  Returns any value of expr including null. This aggregator can simplify and optimize the performance by returning the first encountered value (including null).

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValue is omitted; it defaults to 1024. aggregateMultipleValues is an optional boolean flag controls the behavior of aggregating a multi-value dimension. aggregateMultipleValues is set as true by default and returns the stringified array in case of a multi-value dimension. By setting it to false, function will return first value instead.
  """
  sql_function any_value(expr, max_bytes_per_value)

  @doc """
  Returns any value of expr including null. This aggregator can simplify and optimize the performance by returning the first encountered value (including null).

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValue is omitted; it defaults to 1024. aggregateMultipleValues is an optional boolean flag controls the behavior of aggregating a multi-value dimension. aggregateMultipleValues is set as true by default and returns the stringified array in case of a multi-value dimension. By setting it to false, function will return first value instead.
  """
  sql_function any_value(expr, max_bytes_per_value, aggregate_multiple_values)

  @doc "Returns a number to indicate which groupBy dimension is included in a row, when using GROUPING SETS. Refer to additional documentation on how to infer this number."
  sql_function grouping(exprs)

  @doc "Collects all values of expr into an ARRAY, including null values, with size in bytes limit on aggregation size (default of 1024 bytes). If the aggregated array grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the ARRAY_AGG expression is not currently supported, and the ordering of results within the output array may vary depending on processing order."
  sql_function array_agg(expr)

  @doc "Collects all values of expr into an ARRAY, including null values, with size in bytes limit on aggregation size (default of 1024 bytes). If the aggregated array grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the ARRAY_AGG expression is not currently supported, and the ordering of results within the output array may vary depending on processing order."
  sql_function array_agg(expr, size)

  @doc "Concatenates all array expr into a single ARRAY, with size in bytes limit on aggregation size (default of 1024 bytes). Input expr must be an array. Null expr will be ignored, but any null values within an expr will be included in the resulting array. If the aggregated array grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the ARRAY_CONCAT_AGG expression is not currently supported, and the ordering of results within the output array may vary depending on processing order."
  sql_function array_concat_agg(expr)

  @doc "Concatenates all array expr into a single ARRAY, with size in bytes limit on aggregation size (default of 1024 bytes). Input expr must be an array. Null expr will be ignored, but any null values within an expr will be included in the resulting array. If the aggregated array grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the ARRAY_CONCAT_AGG expression is not currently supported, and the ordering of results within the output array may vary depending on processing order."
  sql_function array_concat_agg(expr, size)

  @doc "Collects all values (or all distinct values) of expr into a single STRING, ignoring null values. Each value is joined by an optional separator, which must be a literal STRING. If the separator is not provided, strings are concatenated without a separator. An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order."
  sql_function string_agg(expr)

  @doc """
  Collects all values (or all distinct values) of expr into a single STRING, ignoring null values. Each value is joined by an optional separator, which must be a literal STRING. If the separator is not provided, strings are concatenated without a separator. An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order.

  An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order.
  """
  sql_function string_agg(expr, separator)

  @doc """
  Collects all values (or all distinct values) of expr into a single STRING, ignoring null values. Each value is joined by an optional separator, which must be a literal STRING. If the separator is not provided, strings are concatenated without a separator. An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order.

  An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order.
  """
  sql_function string_agg(expr, separator, size)

  @doc "Synonym for STRING_AGG."
  sql_function listagg(expr)

  @doc "Synonym for STRING_AGG."
  sql_function listagg(expr, separator)

  @doc "Synonym for STRING_AGG."
  sql_function listagg(expr, separator, size)

  @doc "Performs a bitwise AND operation on all input values."
  sql_function bit_and(expr)

  @doc "Performs a bitwise OR operation on all input values."
  sql_function bit_or(expr)

  @doc "Performs a bitwise XOR operation on all input values."
  sql_function bit_xor(expr)
end
