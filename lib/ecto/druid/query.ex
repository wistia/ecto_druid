defmodule Ecto.Druid.Query do
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  @time_unit ~w(SECOND MINUTE HOUR DAY WEEK MONTH QUARTER YEAR)
  @extended_time_unit @time_unit ++
                        ~w(EPOCH MICROSECOND MILLISECOND DOW ISODOW DOY ISOYEAR DECADE CENTURY MILLENNIUM)

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
    fragment = "EXTRACT(#{unit} FROM ?)"

    quote do
      fragment(unquote(fragment), unquote(timestamp_expr))
    end
  end

  @doc "Rounds down a timestamp, returning it as a new timestamp. Unit can be SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, or YEAR."
  @spec floor(Macro.t(), Macro.t()) :: Macro.t()
  defmacro floor(timestamp_expr, unit) when unit in @extended_time_unit do
    fragment = "FLOOR(? TO #{unit})"

    quote do
      fragment(unquote(fragment), unquote(timestamp_expr))
    end
  end

  @doc "Rounds up a timestamp, returning it as a new timestamp. Unit can be SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, or YEAR."
  @spec ceil(Macro.t(), Macro.t()) :: Macro.t()
  defmacro ceil(timestamp_expr, unit) when unit in @extended_time_unit do
    fragment = "CEIL(? TO #{unit})"

    quote do
      fragment(unquote(fragment), unquote(timestamp_expr))
    end
  end

  @doc "Equivalent to timestamp + count * INTERVAL '1' UNIT."
  @spec timestampadd(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro timestampadd(unit, count, timestamp) when unit in @time_unit do
    fragment = "TIMESTAMPADD(#{unit}, ?, ?)"

    quote do
      fragment(unquote(fragment), unquote(count), unquote(timestamp))
    end
  end

  @doc "Returns the (signed) number of unit between timestamp1 and timestamp2. Unit can be SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, or YEAR."
  @spec timestampdiff(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro timestampdiff(unit, timestamp1, timestamp2) when unit in @time_unit do
    fragment = "TIMESTAMPDIFF(#{unit}, ?, ?)"

    quote do
      fragment(unquote(fragment), unquote(timestamp1), unquote(timestamp2))
    end
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
    clause =
      clauses
      |> Keyword.keys()
      |> Enum.map(fn keyword ->
        keyword
        |> to_string()
        |> String.upcase()
        |> Kernel.<>(" ? ")
      end)

    fragment =
      "CASE ? #{clause}END"

    args = Keyword.values(clauses)

    quote do
      fragment(unquote(fragment), unquote(expr), unquote_splicing(args))
    end
  end

  @doc "Searched CASE."
  defmacro sql_case(clauses) do
    clause =
      clauses
      |> Keyword.keys()
      |> Enum.map(fn keyword ->
        keyword
        |> to_string()
        |> String.upcase()
        |> Kernel.<>(" ? ")
      end)

    fragment =
      "CASE #{clause}END"

    args = Keyword.values(clauses)

    quote do
      fragment(unquote(fragment), unquote_splicing(args))
    end
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

  sql_function table(source)
  sql_function extern(input_source, input_format, row_signature)
  sql_function approx_count_distinct_ds_theta(column, sketch_size)
  sql_function ds_theta(column, sketch_size), type: Ecto.Druid.ThetaSketch
  sql_function ds_quantiles_sketch(column, sketch_size)
  sql_function parse_json(expr)
end
