defmodule Ecto.Druid.Query do
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]

  # Numeric functions

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

  # String functions
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

  sql_function table(source)
  sql_function extern(input_source, input_format, row_signature)
  sql_function approx_count_distinct_ds_theta(column, sketch_size)
  sql_function ds_theta(column, sketch_size), type: Ecto.Druid.ThetaSketch
  sql_function ds_quantiles_sketch(column, sketch_size)
  sql_function ds_histogram(column, split_points), type: Ecto.Druid.Histogram
  sql_function parse_json(expr)
end
