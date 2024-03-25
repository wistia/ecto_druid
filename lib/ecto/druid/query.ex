defmodule Ecto.Druid.Query do
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @time_unit ~w(SECOND MINUTE HOUR DAY WEEK MONTH QUARTER YEAR)
  @extended_time_unit @time_unit ++
                        ~w(EPOCH MICROSECOND MILLISECOND DOW ISODOW DOY ISOYEAR DECADE CENTURY MILLENNIUM)

  # Keyword like functions

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

  # Scalar functions
  ## Numeric functions

  @doc "Constant Pi."
  sql_function pi()
  @doc "Absolute value."
  sql_function abs(expr)
  @doc "Ceiling."
  sql_function ceil(expr)
  @doc "e to the power of expr."
  sql_function exp(expr)
  @doc "Floor."
  sql_function floor(expr)
  @doc "Logarithm (base e)."
  sql_function ln(expr)
  @doc "Logarithm (base 10)."
  sql_function log10(expr)
  @doc "expr raised to the power of power."
  sql_function power(expr, power)
  @doc "Square root."
  sql_function sqrt(expr)
  @doc "Truncate expr to a specific number of decimal digits."
  sql_function truncate(expr)
  @doc "Truncate expr to a specific number of decimal digits."
  sql_function truncate(expr, digits)
  @doc "Alias for TRUNCATE."
  sql_function trunc(expr)
  @doc "Alias for TRUNCATE."
  sql_function trunc(expr, digits)
  @doc "ROUND(x, y) would return the value of the x rounded to the y decimal places."
  sql_function round(expr)
  @doc "ROUND(x, y) would return the value of the x rounded to the y decimal places."
  sql_function round(expr, digits)
  @doc "Modulo (remainder of x divided by y)."
  sql_function mod(x, y)
  @doc "Trigonometric sine of an angle expr."
  sql_function sin(expr)
  @doc "Trigonometric cosine of an angle expr."
  sql_function cos(expr)
  @doc "Trigonometric tangent of an angle expr."
  sql_function tan(expr)
  @doc "Trigonometric cotangent of an angle expr."
  sql_function cot(expr)
  @doc "Arc sine of expr."
  sql_function asin(expr)
  @doc "Arc cosine of expr."
  sql_function acos(expr)
  @doc "Arc tangent of expr."
  sql_function atan(expr)

  @doc "Angle theta from the conversion of rectangular coordinates (x, y) to polar coordinates (r, theta)."
  sql_function atan2(y, x)

  @doc "Converts an angle measured in radians to an approximately equivalent angle measured in degrees."
  sql_function degrees(expr)

  @doc "Converts an angle measured in degrees to an approximately equivalent angle measured in radians."
  sql_function radians(expr)
  @doc "Returns the result of expr1 & expr2."
  sql_function bitwise_and(x, y)
  @doc "Returns the result of ~expr."
  sql_function bitwise_complement(expr)
  @doc "Converts the bits of an IEEE 754 floating-point double value to a long."
  sql_function bitwise_convert_double_to_long_bits(expr)

  @doc "Converts a long to the IEEE 754 floating-point double specified by the bits stored in the long."
  sql_function bitwise_convert_long_bits_to_double(expr)
  @doc "Returns the result of expr1 [PIPE] expr2."
  sql_function bitwise_or(x, y)
  @doc "Returns the result of expr1 << expr2."
  sql_function bitwise_shift_left(x, y)
  @doc "Returns the result of expr1 >> expr2."
  sql_function bitwise_shift_right(x, y)
  @doc "Returns the result of expr1 ^ expr2."
  sql_function bitwise_xor(x, y)
  @doc "Returns the result of integer division of x by y"
  sql_function div(x, y)
  @doc "Format a number in human-readable IEC format."
  sql_function human_readable_binary_byte_format(value)
  @doc "Format a number in human-readable IEC format."
  sql_function human_readable_binary_byte_format(value, precision)
  @doc "Format a number in human-readable SI format."
  sql_function human_readable_decimal_byte_format(value)
  @doc "Format a number in human-readable SI format."
  sql_function human_readable_decimal_byte_format(value, precision)
  @doc "Format a number in human-readable SI format."
  sql_function human_readable_decimal_format(value)
  @doc "Format a number in human-readable SI format."
  sql_function human_readable_decimal_format(value, precision)
  @doc "Returns the division of x by y guarded on division by 0."
  sql_function safe_divide(x, y)

  ## String functions
  @doc "Concats a list of expressions."
  sql_function concat(exprs)
  @doc "Two argument version of CONCAT."
  sql_function textcat(expr1, expr2)
  @doc "Returns true if the str is a substring of expr."
  sql_function contains_string(expr, str)
  @doc "Returns true if the str is a substring of expr. The match is case-insensitive."
  sql_function icontains_string(expr, str)
  @doc "Decodes a Base64-encoded string into a UTF-8 encoded string."
  sql_function decode_base64_utf8(expr)
  @doc "Returns the leftmost length characters from expr."
  sql_function left(expr)
  @doc "Returns the leftmost length characters from expr."
  sql_function left(expr, length)
  @doc "Returns the rightmost length characters from expr."
  sql_function right(expr)
  @doc "Returns the rightmost length characters from expr."
  sql_function right(expr, length)
  @doc "Length of expr in UTF-16 code units."
  sql_function length(expr)
  @doc "Alias for LENGTH."
  sql_function char_length(expr)
  @doc "Alias for LENGTH."
  sql_function character_length(expr)
  @doc "Alias for LENGTH."
  sql_function strlen(expr)

  @doc "Look up expr in a registered query-time lookup table. Note that lookups can also be queried directly using the lookup schema. Optional constant replaceMissingValueWith can be passed as a third argument to be returned when value is missing from lookup."
  sql_function lookup(expr, lookup_name)

  @doc "Look up expr in a registered query-time lookup table. Note that lookups can also be queried directly using the lookup schema. Optional constant replaceMissingValueWith can be passed as a third argument to be returned when value is missing from lookup."
  sql_function lookup(expr, lookup_name, replace_missing_value_with)
  @doc "Returns expr in all lowercase."
  sql_function lower(expr)
  @doc "Returns expr in all uppercase."
  sql_function upper(expr)

  @doc "Returns a string of length from expr left-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function lpad(expr, length)

  @doc "Returns a string of length from expr left-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function lpad(expr, length, chars)

  @doc "Returns a string of length from expr right-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function rpad(expr, length)

  @doc "Returns a string of length from expr right-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function rpad(expr, length, chars)

  @doc "Parses a string into a long (BIGINT) with the given radix, or 10 (decimal) if a radix is not provided."
  sql_function parse_long(string)

  @doc "Parses a string into a long (BIGINT) with the given radix, or 10 (decimal) if a radix is not provided."
  sql_function parse_long(string, radix)

  @doc "Returns the index of needle within haystack, with indexes starting from 1. The search will begin at fromIndex, or 1 if fromIndex is not specified. If needle is not found, returns 0."
  sql_function position(needle, haystack), placeholders: "? IN ?"

  @doc "Returns the index of needle within haystack, with indexes starting from 1. The search will begin at fromIndex, or 1 if fromIndex is not specified. If needle is not found, returns 0."
  sql_function position(needle, haystack, from_index), placeholders: "? IN ? FROM ?"

  @doc "Apply regular expression pattern to expr and extract a capture group, or NULL if there is no match. If index is unspecified or zero, returns the first substring that matched the pattern. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern. Note: when druid.generic.useDefaultValueForNull = true, it is not possible to differentiate an empty-string match from a non-match (both will return NULL)."
  sql_function regexp_extract(expr, pattern)

  @doc "Apply regular expression pattern to expr and extract a capture group, or NULL if there is no match. If index is unspecified or zero, returns the first substring that matched the pattern. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern. Note: when druid.generic.useDefaultValueForNull = true, it is not possible to differentiate an empty-string match from a non-match (both will return NULL)."
  sql_function regexp_extract(expr, pattern, index)

  @doc "Returns whether expr matches regular expression pattern. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern. Similar to LIKE, but uses regexps instead of LIKE patterns. Especially useful in WHERE clauses."
  sql_function regexp_like(expr, pattern)

  @doc "Replaces all occurrences of regular expression pattern within expr with replacement. The replacement string may refer to capture groups using $1, $2, etc. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern."
  sql_function regexp_replace(expr, pattern, replacement)
  @doc "Replaces pattern with replacement in expr, and returns the result."
  sql_function replace(expr, pattern, replacement)
  @doc "Repeats expr N times."
  sql_function repeat(expr, n)
  @doc "Reverses expr."
  sql_function reverse(expr)
  @doc "Returns a string formatted in the manner of Java's String.format."
  sql_function string_format(pattern, args)

  @doc "Returns the index of needle within haystack, with indexes starting from 1. If needle is not found, returns 0."
  sql_function strpos(haystack, needle)

  @doc "Returns a substring of expr starting at index, with a max length, both measured in UTF-16 code units."
  sql_function substring(expr, index)

  @doc "Returns a substring of expr starting at index, with a max length, both measured in UTF-16 code units."
  sql_function substring(expr, index, length)
  @doc "Alias for SUBSTRING."
  sql_function substr(expr, index)
  @doc "Alias for SUBSTRING."
  sql_function substr(expr, index, length)

  @doc "Returns expr with characters removed from the leading, trailing, or both ends of expr if they are in chars. If chars is not provided, it defaults to '' (a space). If the directional argument is not provided, it defaults to BOTH."
  sql_function trim(expr)

  @doc "Returns expr with characters removed from the leading, trailing, or both ends of expr if they are in chars. If chars is not provided, it defaults to '' (a space). If the directional argument is not provided, it defaults to BOTH."
  sql_function trim(chars, expr), placeholders: "? FROM ?"
  @doc "Alternate form of TRIM(BOTH chars FROM expr)."
  sql_function btrim(expr)
  @doc "Alternate form of TRIM(BOTH chars FROM expr)."
  sql_function btrim(expr, chars)
  @doc "Alternate form of TRIM(LEADING chars FROM expr)."
  sql_function ltrim(expr)
  @doc "Alternate form of TRIM(LEADING chars FROM expr)."
  sql_function ltrim(expr, chars)
  @doc "Alternate form of TRIM(TRAILING chars FROM expr)."
  sql_function rtrim(expr)
  @doc "Alternate form of TRIM(TRAILING chars FROM expr)."
  sql_function rtrim(expr, chars)

  ## Date and time functions

  @doc "Current timestamp in the connection's time zone."
  sql_function current_timestamp()
  @doc "Current date in the connection's time zone."
  sql_function current_date()

  @doc "Rounds down a timestamp, returning it as a new timestamp. Unit can be 'milliseconds', 'second', 'minute', 'hour', 'day', 'week', 'month', 'quarter', 'year', 'decade', 'century', or 'millennium'."
  sql_function date_trunc(unit, timestamp_expr)

  @doc "Rounds up a timestamp, returning it as a new timestamp. Period can be any ISO8601 period, like P3M (quarters) or PT12H (half-days). Specify origin as a timestamp to set the reference time for rounding. For example, TIME_CEIL(__time, 'PT1H', TIMESTAMP '2016-06-27 00:30:00') measures an hourly period from 00:30-01:30 instead of 00:00-01:00. See Period granularities for details on the default starting boundaries. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to CEIL but is more flexible."
  sql_function time_ceil(timestamp_expr, period)

  @doc "Rounds up a timestamp, returning it as a new timestamp. Period can be any ISO8601 period, like P3M (quarters) or PT12H (half-days). Specify origin as a timestamp to set the reference time for rounding. For example, TIME_CEIL(__time, 'PT1H', TIMESTAMP '2016-06-27 00:30:00') measures an hourly period from 00:30-01:30 instead of 00:00-01:00. See Period granularities for details on the default starting boundaries. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to CEIL but is more flexible."
  sql_function time_ceil(timestamp_expr, period, origin)

  @doc "Rounds up a timestamp, returning it as a new timestamp. Period can be any ISO8601 period, like P3M (quarters) or PT12H (half-days). Specify origin as a timestamp to set the reference time for rounding. For example, TIME_CEIL(__time, 'PT1H', TIMESTAMP '2016-06-27 00:30:00') measures an hourly period from 00:30-01:30 instead of 00:00-01:00. See Period granularities for details on the default starting boundaries. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to CEIL but is more flexible."
  sql_function time_ceil(timestamp_expr, period, origin, timezone)

  @doc "Rounds down a timestamp, returning it as a new timestamp. Period can be any ISO8601 period, like P3M (quarters) or PT12H (half-days). Specify origin as a timestamp to set the reference time for rounding. For example, TIME_FLOOR(__time, 'PT1H', TIMESTAMP '2016-06-27 00:30:00') measures an hourly period from 00:30-01:30 instead of 00:00-01:00. See Period granularities for details on the default starting boundaries. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to FLOOR but is more flexible."
  sql_function time_floor(timestamp_expr, period)

  @doc "Rounds down a timestamp, returning it as a new timestamp. Period can be any ISO8601 period, like P3M (quarters) or PT12H (half-days). Specify origin as a timestamp to set the reference time for rounding. For example, TIME_FLOOR(__time, 'PT1H', TIMESTAMP '2016-06-27 00:30:00') measures an hourly period from 00:30-01:30 instead of 00:00-01:00. See Period granularities for details on the default starting boundaries. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to FLOOR but is more flexible."
  sql_function time_floor(timestamp_expr, period, origin)

  @doc "Rounds down a timestamp, returning it as a new timestamp. Period can be any ISO8601 period, like P3M (quarters) or PT12H (half-days). Specify origin as a timestamp to set the reference time for rounding. For example, TIME_FLOOR(__time, 'PT1H', TIMESTAMP '2016-06-27 00:30:00') measures an hourly period from 00:30-01:30 instead of 00:00-01:00. See Period granularities for details on the default starting boundaries. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to FLOOR but is more flexible."
  sql_function time_floor(timestamp_expr, period, origin, timezone)

  @doc "Shifts a timestamp by a period (step times), returning it as a new timestamp. Period can be any ISO8601 period. Step may be negative. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'."
  sql_function time_shift(timestamp_expr, period, step)

  @doc "Shifts a timestamp by a period (step times), returning it as a new timestamp. Period can be any ISO8601 period. Step may be negative. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'."
  sql_function time_shift(timestamp_expr, period, step, timezone)

  @doc "Extracts a time part from expr, returning it as a number. Unit can be EPOCH, SECOND, MINUTE, HOUR, DAY (day of month), DOW (day of week), DOY (day of year), WEEK (week of week year), MONTH (1 through 12), QUARTER (1 through 4), or YEAR. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to EXTRACT but is more flexible. Unit and time zone must be literals, and must be provided quoted, like TIME_EXTRACT(__time, 'HOUR') or TIME_EXTRACT(__time, 'HOUR', 'America/Los_Angeles')."
  sql_function time_extract(timestamp_expr, unit)

  @doc "Extracts a time part from expr, returning it as a number. Unit can be EPOCH, SECOND, MINUTE, HOUR, DAY (day of month), DOW (day of week), DOY (day of year), WEEK (week of week year), MONTH (1 through 12), QUARTER (1 through 4), or YEAR. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. This function is similar to EXTRACT but is more flexible. Unit and time zone must be literals, and must be provided quoted, like TIME_EXTRACT(__time, 'HOUR') or TIME_EXTRACT(__time, 'HOUR', 'America/Los_Angeles')."
  sql_function time_extract(timestamp_expr, unit, timezone)

  @doc "Parses a string into a timestamp using a given Joda DateTimeFormat pattern, or ISO8601 (e.g. 2000-01-02T03:04:05Z) if the pattern is not provided. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00', and will be used as the time zone for strings that do not include a time zone offset. Pattern and time zone must be literals. Strings that cannot be parsed as timestamps will be returned as NULL."
  sql_function time_parse(string_expr)

  @doc "Parses a string into a timestamp using a given Joda DateTimeFormat pattern, or ISO8601 (e.g. 2000-01-02T03:04:05Z) if the pattern is not provided. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00', and will be used as the time zone for strings that do not include a time zone offset. Pattern and time zone must be literals. Strings that cannot be parsed as timestamps will be returned as NULL."
  sql_function time_parse(string_expr, pattern)

  @doc "Parses a string into a timestamp using a given Joda DateTimeFormat pattern, or ISO8601 (e.g. 2000-01-02T03:04:05Z) if the pattern is not provided. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00', and will be used as the time zone for strings that do not include a time zone offset. Pattern and time zone must be literals. Strings that cannot be parsed as timestamps will be returned as NULL."
  sql_function time_parse(string_expr, pattern, timezone)

  @doc "Formats a timestamp as a string with a given Joda DateTimeFormat pattern, or ISO8601 (e.g. 2000-01-02T03:04:05Z) if the pattern is not provided. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. Pattern and time zone must be literals."
  sql_function time_format(timestamp_expr)

  @doc "Formats a timestamp as a string with a given Joda DateTimeFormat pattern, or ISO8601 (e.g. 2000-01-02T03:04:05Z) if the pattern is not provided. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. Pattern and time zone must be literals."
  sql_function time_format(timestamp_expr, pattern)

  @doc "Formats a timestamp as a string with a given Joda DateTimeFormat pattern, or ISO8601 (e.g. 2000-01-02T03:04:05Z) if the pattern is not provided. The time zone, if provided, should be a time zone name like 'America/Los_Angeles' or offset like '-08:00'. Pattern and time zone must be literals."
  sql_function time_format(timestamp_expr, pattern, timezone)

  @doc "Returns whether a timestamp is contained within a particular interval. The interval must be a literal string containing any ISO8601 interval, such as '2001-01-01/P1D' or '2001-01-01T01:00:00/2001-01-02T01:00:00'. The start instant of the interval is inclusive and the end instant is exclusive."
  sql_function time_in_interval(timestamp_expr, interval)

  @doc "Converts a number of milliseconds since the epoch (1970-01-01 00:00:00 UTC) into a timestamp."
  sql_function millis_to_timestamp(millis_expr)
  @doc "Converts a timestamp into a number of milliseconds since the epoch."
  sql_function timestamp_to_millis(timestamp_expr)

  @doc "Extracts a time part from expr, returning it as a number. Unit can be EPOCH, MICROSECOND, MILLISECOND, SECOND, MINUTE, HOUR, DAY, DOW (day of week), ISODOW (ISO day of week), DOY (day of year), WEEK (week of year), MONTH, QUARTER, YEAR, ISOYEAR, DECADE, CENTURY or MILLENNIUM. Units must be provided unquoted, like EXTRACT(HOUR FROM __time)."
  @spec extract(Macro.t(), Macro.t()) :: Macro.t()
  defmacro extract(unit, timestamp_expr) when unit in @extended_time_unit do
    Ecto.Druid.Util.sql_function_body(
      "EXTRACT",
      "#{unit} FROM ?",
      [timestamp_expr]
    )
  end

  @doc "Rounds down a timestamp, returning it as a new timestamp. Unit can be SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, or YEAR."
  @spec floor(Macro.t(), Macro.t()) :: Macro.t()
  defmacro floor(timestamp_expr, unit) when unit in @extended_time_unit do
    Ecto.Druid.Util.sql_function_body(
      "FLOOR",
      "? TO #{unit}",
      [timestamp_expr]
    )
  end

  @doc "Rounds up a timestamp, returning it as a new timestamp. Unit can be SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, or YEAR."
  @spec ceil(Macro.t(), Macro.t()) :: Macro.t()
  defmacro ceil(timestamp_expr, unit) when unit in @extended_time_unit do
    Ecto.Druid.Util.sql_function_body(
      "CEIL",
      "? TO #{unit}",
      [timestamp_expr]
    )
  end

  @doc "Equivalent to timestamp + count * INTERVAL '1' UNIT."
  @spec timestampadd(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro timestampadd(unit, count, timestamp) when unit in @time_unit do
    Ecto.Druid.Util.sql_function_body(
      "TIMESTAMPADD",
      "#{unit}, ?, ?",
      [count, timestamp]
    )
  end

  @doc "Returns the (signed) number of unit between timestamp1 and timestamp2. Unit can be SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, or YEAR."
  @spec timestampdiff(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro timestampdiff(unit, timestamp1, timestamp2) when unit in @time_unit do
    Ecto.Druid.Util.sql_function_body(
      "TIMESTAMPDIFF",
      "#{unit}, ?, ?",
      [timestamp1, timestamp2]
    )
  end

  ## Reduction functions

  @doc "Evaluates zero or more expressions and returns the maximum value based on comparisons as described above."
  sql_function greatest(exprs)

  @doc "Evaluates zero or more expressions and returns the minimum value based on comparisons as described above."
  sql_function least(exprs)

  # IP address functions

  @doc "Returns true if the address belongs to the subnet literal, else false. If address is not a valid IPv4 address, then false is returned. This function is more efficient if address is an integer instead of a string."
  sql_function ipv4_match(address, subnet)

  @doc "Parses address into an IPv4 address stored as an integer . If address is an integer that is a valid IPv4 address, then it is passed through. Returns null if address cannot be represented as an IPv4 address."
  sql_function ipv4_parse(address)

  @doc "Converts address into an IPv4 address dotted-decimal string. If address is a string that is a valid IPv4 address, then it is passed through. Returns null if address cannot be represented as an IPv4 address."
  sql_function ipv4_stringify(address)

  @doc "Returns 1 if the IPv6 address belongs to the subnet literal, else 0. If address is not a valid IPv6 address, then 0 is returned."
  sql_function ipv6_match(address, subnet)

  ## HLL sketch functions

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

  ## Theta sketch functions

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

  ## Quantiles sketch functions

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

  ## Tuple sketch functions

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

  ## Other scaler functions

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

  # Aggregate functions

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
  sql_function approx_quantile(expr, probability)

  @doc """
  Deprecated. Use APPROX_QUANTILE_DS instead, which provides a superior distribution-independent algorithm with formal error guarantees.

  Computes approximate quantiles on numeric or approxHistogram expressions. probability should be between 0 and 1, exclusive. resolution is the number of centroids to use for the computation. Higher resolutions will give more precise results but also have higher overhead. If not provided, the default resolution is 50. Load the approximate histogram extension to use this function.
  """
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

  @doc "Computes a bloom filter from values produced by expr, with numEntries maximum number of distinct values before false positive rate increases. See bloom filter extension documentation for additional details.	Empty base64 encoded bloom filter"
  sql_function bloom_filter(expr, num_entries)

  @doc "Computes variance population of expr. See stats extension documentation for additional details.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function var_pop(expr)

  @doc "Computes variance sample of expr. See stats extension documentation for additional details.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function var_samp(expr)

  @doc "Computes variance sample of expr. See stats extension documentation for additional details.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function variance(expr)

  @doc "Computes standard deviation population of expr. See stats extension documentation for additional details.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function stddev_pop(expr)

  @doc "Computes standard deviation sample of expr. See stats extension documentation for additional details.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function stddev_samp(expr)

  @doc "Computes standard deviation sample of expr. See stats extension documentation for additional details.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function stddev(expr)

  @doc """
  Returns the earliest value of expr.
  If expr comes from a relation with a timestamp column (like __time in a Druid datasource), the "earliest" is taken from the row with the overall earliest non-null value of the timestamp column.
  If the earliest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows. If expr does not come from a relation with a timestamp, then it is simply the first value encountered.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function earliest(expr)

  @doc """
  Returns the earliest value of expr.
  If expr comes from a relation with a timestamp column (like __time in a Druid datasource), the "earliest" is taken from the row with the overall earliest non-null value of the timestamp column.
  If the earliest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows. If expr does not come from a relation with a timestamp, then it is simply the first value encountered.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function earliest(expr, max_bytes_per_value)

  @doc """
  Returns the earliest value of expr.
  The earliest value of expr is taken from the row with the overall earliest non-null value of timestampExpr.
  If the earliest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use EARLIEST instead of EARLIEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function earliest_by(expr, timestamp_expr)

  @doc """
  Returns the earliest value of expr.
  The earliest value of expr is taken from the row with the overall earliest non-null value of timestampExpr.
  If the overall earliest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use EARLIEST instead of EARLIEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function earliest_by(expr, timestamp_expr, max_bytes_per_value)

  @doc """
  Returns the latest value of expr
  The expr must come from a relation with a timestamp column (like __time in a Druid datasource) and the "latest" is taken from the row with the overall latest non-null value of the timestamp column.
  If the latest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function latest(expr)

  @doc """
  Returns the latest value of expr
  The expr must come from a relation with a timestamp column (like __time in a Druid datasource) and the "latest" is taken from the row with the overall latest non-null value of the timestamp column.
  If the latest non-null value of the timestamp column appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function latest(expr, max_bytes_per_value)

  @doc """
  Returns the latest value of expr
  The latest value of expr is taken from the row with the overall latest non-null value of timestampExpr.
  If the overall latest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use LATEST instead of LATEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function latest_by(expr, timestamp_expr)

  @doc """
  Returns the latest value of expr
  The latest value of expr is taken from the row with the overall latest non-null value of timestampExpr.
  If the overall latest non-null value of timestampExpr appears in multiple rows, the expr may be taken from any of those rows.

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValueis omitted; it defaults to 1024.

  Use LATEST instead of LATEST_BY on a table that has rollup enabled and was created with any variant of EARLIEST, LATEST, EARLIEST_BY, or LATEST_BY. In these cases, the intermediate type already stores the timestamp, and Druid ignores the value passed in timestampExpr.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function latest_by(expr, timestamp_expr, max_bytes_per_value)

  @doc """
  Returns any value of expr including null. This aggregator can simplify and optimize the performance by returning the first encountered value (including null).

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValue is omitted; it defaults to 1024. aggregateMultipleValues is an optional boolean flag controls the behavior of aggregating a multi-value dimension. aggregateMultipleValues is set as true by default and returns the stringified array in case of a multi-value dimension. By setting it to false, function will return first value instead.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function any_value(expr)

  @doc """
  Returns any value of expr including null. This aggregator can simplify and optimize the performance by returning the first encountered value (including null).

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValue is omitted; it defaults to 1024. aggregateMultipleValues is an optional boolean flag controls the behavior of aggregating a multi-value dimension. aggregateMultipleValues is set as true by default and returns the stringified array in case of a multi-value dimension. By setting it to false, function will return first value instead.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function any_value(expr, max_bytes_per_value)

  @doc """
  Returns any value of expr including null. This aggregator can simplify and optimize the performance by returning the first encountered value (including null).

  If expr is a string or complex type maxBytesPerValue amount of space is allocated for the aggregation. Strings longer than this limit are truncated. The maxBytesPerValue parameter should be set as low as possible, since high values will lead to wasted memory.
  If maxBytesPerValue is omitted; it defaults to 1024. aggregateMultipleValues is an optional boolean flag controls the behavior of aggregating a multi-value dimension. aggregateMultipleValues is set as true by default and returns the stringified array in case of a multi-value dimension. By setting it to false, function will return first value instead.	null or 0/'' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
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

  An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order.	null or '' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function string_agg(expr, separator)

  @doc """
  Collects all values (or all distinct values) of expr into a single STRING, ignoring null values. Each value is joined by an optional separator, which must be a literal STRING. If the separator is not provided, strings are concatenated without a separator. An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order.

  An optional size in bytes can be supplied to limit aggregation size (default of 1024 bytes). If the aggregated string grows larger than the maximum size in bytes, the query will fail. Use of ORDER BY within the STRING_AGG expression is not currently supported, and the ordering of results within the output string may vary depending on processing order.	null or '' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)
  """
  sql_function string_agg(expr, separator, size)

  @doc "Synonym for STRING_AGG.	null or '' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function listagg(expr)

  @doc "Synonym for STRING_AGG.	null or '' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function listagg(expr, separator)

  @doc "Synonym for STRING_AGG.	null or '' if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function listagg(expr, separator, size)

  @doc "Performs a bitwise AND operation on all input values.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function bit_and(expr)

  @doc "Performs a bitwise OR operation on all input values.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function bit_or(expr)

  @doc "Performs a bitwise XOR operation on all input values.	null or 0 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)"
  sql_function bit_xor(expr)

  ## Theta sketch aggregations

  @doc "Counts distinct values of expr, which can be a regular column or a Theta sketch column. Results are always approximate, regardless of the value of useApproximateCountDistinct. The size parameter is described in the Theta sketch documentation. See also COUNT(DISTINCT expr)."
  sql_function approx_count_distinct_ds_theta(column)

  @doc "Counts distinct values of expr, which can be a regular column or a Theta sketch column. Results are always approximate, regardless of the value of useApproximateCountDistinct. The size parameter is described in the Theta sketch documentation. See also COUNT(DISTINCT expr)."
  sql_function approx_count_distinct_ds_theta(column, sketch_size)

  @doc "Creates a Theta sketch on the values of expr, which can be a regular column or a column containing Theta sketches. The size parameter is described in the Theta sketch documentation."
  sql_function ds_theta(column), type: Ecto.Druid.ThetaSketch

  @doc "Creates a Theta sketch on the values of expr, which can be a regular column or a column containing Theta sketches. The size parameter is described in the Theta sketch documentation."
  sql_function ds_theta(column, sketch_size), type: Ecto.Druid.ThetaSketch

  ## Quantiles sketch aggregations

  @doc "Computes approximate quantiles on numeric or Quantiles sketch expressions. The probability value should be between 0 and 1, exclusive. The k parameter is described in the Quantiles sketch documentation."
  sql_function approx_quantile_ds(expr, probability)

  @doc "Computes approximate quantiles on numeric or Quantiles sketch expressions. The probability value should be between 0 and 1, exclusive. The k parameter is described in the Quantiles sketch documentation."
  sql_function approx_quantile_ds(expr, probability, sketch_size)

  @doc "Creates a Quantiles sketch on the values of expr, which can be a regular column or a column containing quantiles sketches. The k parameter is described in the Quantiles sketch documentation."
  sql_function ds_quantiles_sketch(expr), type: Ecto.Druid.QuantilesSketch

  @doc "Creates a Quantiles sketch on the values of expr, which can be a regular column or a column containing quantiles sketches. The k parameter is described in the Quantiles sketch documentation."
  sql_function ds_quantiles_sketch(expr, sketch_size), type: Ecto.Druid.QuantilesSketch

  ## Tuple sketch aggregations

  @doc "Creates a Tuple sketch on the values of expr, which can be a regular column or a column containing tuple sketches. The k parameter is described in the Tuple sketch documentation."
  sql_function ds_tuple_doubles(expr), type: Ecto.Druid.TupleSketch

  @doc "Creates a Tuple sketch on the values of expr, which can be a regular column or a column containing tuple sketches. The k parameter is described in the Tuple sketch documentation."
  sql_function ds_tuple_doubles(expr, nominal_entries), type: Ecto.Druid.TupleSketch

  ## T-Digest sketch aggregations

  @doc "Builds a T-Digest sketch on values produced by expr and returns the value for the quantile. Compression parameter (default value 100) determines the accuracy and size of the sketch. Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_quantile(expr, quantile_fraction)

  @doc "Builds a T-Digest sketch on values produced by expr and returns the value for the quantile. Compression parameter (default value 100) determines the accuracy and size of the sketch. Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_quantile(expr, quantile_fraction, compression)

  @doc "Builds a T-Digest sketch on values produced by expr. Compression parameter (default value 100) determines the accuracy and size of the sketch Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_generate_sketch(expr)

  @doc "Builds a T-Digest sketch on values produced by expr. Compression parameter (default value 100) determines the accuracy and size of the sketch Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_generate_sketch(expr, compression)

  # Array functions

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

  @doc "Returns the 0-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null or -1 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)."
  sql_function array_offset_of(arr, expr)

  @doc "Returns the 1-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null or -1 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)."
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

  # Multi-value string functions

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

  @doc "Returns the 0-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null or -1 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)."
  sql_function mv_offset_of(arr, expr)

  @doc "Returns the 1-based index of the first occurrence of expr in the array. If no matching elements exist in the array, returns null or -1 if druid.generic.useDefaultValueForNull=true (deprecated legacy mode)."
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

  # JSON functions

  @doc "Returns an array of field names from expr at the specified path."
  sql_function json_keys(expr, path)

  @doc "Constructs a new COMPLEX<json> object. The KEY expressions must evaluate to string types. The VALUE expressions can be composed of any input type, including other COMPLEX<json> values. JSON_OBJECT can accept colon-separated key-value pairs. The following syntax is equivalent: JSON_OBJECT(expr1:expr2[, expr3:expr4, ...])."
  defmacro json_object(kv_pairs) do
    placeholders = kv_pairs |> Enum.map(fn _ -> "KEY ? VALUE ?" end) |> Enum.join(", ")
    args = kv_pairs |> Enum.flat_map(fn {k, v} -> [to_string(k), v] end)

    Ecto.Druid.Util.sql_function_body(
      "JSON_OBJECT",
      placeholders,
      args
    )
  end

  @doc "Returns an array of all paths which refer to literal values in expr in JSONPath format."
  sql_function json_paths(expr)

  @doc "Extracts a COMPLEX<json> value from expr, at the specified path."
  sql_function json_query(expr, path)

  @doc "Extracts an ARRAY<COMPLEX<json>> value from expr at the specified path. If value is not an ARRAY, it gets translated into a single element ARRAY containing the value at path. The primary use of this function is to extract arrays of objects to use as inputs to other array functions."
  sql_function json_query_array(expr, path)

  @doc "Extracts a literal value from expr at the specified path. If you specify RETURNING and an SQL type name (such as VARCHAR, BIGINT, DOUBLE, etc) the function plans the query using the suggested type. Otherwise, it attempts to infer the type based on the context. If it can't infer the type, it defaults to VARCHAR."
  sql_function json_value(expr, path)

  @doc "Extracts a literal value from expr at the specified path. If you specify RETURNING and an SQL type name (such as VARCHAR, BIGINT, DOUBLE, etc) the function plans the query using the suggested type. Otherwise, it attempts to infer the type based on the context. If it can't infer the type, it defaults to VARCHAR."
  sql_function json_value(expr, path, type), placeholders: "?, ? RETURNING ?"

  @doc "Parses expr into a COMPLEX<json> object. This operator deserializes JSON values when processing them, translating stringified JSON into a nested structure. If the input is not a VARCHAR or it is invalid JSON, this function will result in an error."
  sql_function parse_json(expr)

  @doc "Parses expr into a COMPLEX<json> object. This operator deserializes JSON values when processing them, translating stringified JSON into a nested structure. If the input is not a VARCHAR or it is invalid JSON, this function will result in a NULL value."
  sql_function try_parse_json(expr)

  @doc "Serializes expr into a JSON string."
  sql_function to_json_string(expr)

  # Table functions
  sql_function table(source)
  sql_function extern(input_source, input_format, row_signature)
end
