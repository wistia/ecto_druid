defmodule Ecto.Druid.Query.Numeric do
  @moduledoc """
  Druid numeric [scalar functions](https://druid.apache.org/docs/latest/querying/sql-scalar#numeric-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1]
  @doc "Constant Pi."
  sql_function pi()
  @doc "Absolute value."
  sql_function abs_(expr)
  @doc "Ceiling."
  sql_function ceil_(expr)
  @doc "e to the power of expr."
  sql_function exp(expr)
  @doc "Floor."
  sql_function floor_(expr)
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
  sql_function trunc_(expr)
  @doc "Alias for TRUNCATE."
  sql_function trunc_(expr, digits)
  @doc "ROUND(x, y) would return the value of the x rounded to the y decimal places."
  sql_function round_(expr)
  @doc "ROUND(x, y) would return the value of the x rounded to the y decimal places."
  sql_function round_(expr, digits)
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
  @doc "Returns the result of expr1 | expr2."
  sql_function bitwise_or(x, y)
  @doc "Returns the result of expr1 << expr2."
  sql_function bitwise_shift_left(x, y)
  @doc "Returns the result of expr1 >> expr2."
  sql_function bitwise_shift_right(x, y)
  @doc "Returns the result of expr1 ^ expr2."
  sql_function bitwise_xor(x, y)
  @doc "Returns the result of integer division of x by y"
  sql_function div_(x, y)
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
end
