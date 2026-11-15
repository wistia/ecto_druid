defmodule Ecto.Druid.Query.DateTime do
  @moduledoc """
  Druid [date and time functions](https://druid.apache.org/docs/latest/querying/sql-scalar#date-and-time-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1]

  @time_unit ~w(SECOND MINUTE HOUR DAY WEEK MONTH QUARTER YEAR)
  @extended_time_unit @time_unit ++
                        ~w(EPOCH MICROSECOND MILLISECOND DOW ISODOW DOY ISOYEAR DECADE CENTURY MILLENNIUM)
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

  @doc """
  Returns whether a timestamp is contained within a particular interval, using Druid's `TIME_IN_INTERVAL`. The start
  instant of the interval is inclusive and the end instant is exclusive.

  The interval is either:

    * an ISO8601 interval string, such as `"2001-01-01/P1D"` or `"2001-01-01T01:00:00/2001-01-02T01:00:00"`, or
    * a `{start, stop}` tuple of `DateTime`s, `NaiveDateTime`s, `Date`s or ISO8601 strings, which is converted to an
      interval string like `"2001-01-01T00:00:00Z/2001-01-02T00:00:00Z"`.

  The interval may be pinned (`^interval`, `^{start, stop}`), and a tuple's bounds may be pinned individually
  (`{^start, ^stop}`). A tuple is always sent as a parameter, since it's converted when the query runs.
  """
  @spec time_in_interval(Macro.t(), Macro.t()) :: Macro.t()
  defmacro time_in_interval(timestamp_expr, interval) do
    Ecto.Druid.Util.sql_function_body("TIME_IN_INTERVAL", nil, [
      timestamp_expr,
      interval_param(interval)
    ])
  end

  defp interval_param({start, stop}) do
    interval =
      quote do:
              Ecto.Druid.Query.DateTime.to_interval({unquote(unpin(start)), unquote(unpin(stop))})

    {:^, [], [interval]}
  end

  defp interval_param({:^, meta, [interval]}) do
    {:^, meta, [quote(do: Ecto.Druid.Query.DateTime.to_interval(unquote(interval)))]}
  end

  defp interval_param(interval), do: interval

  defp unpin({:^, _, [value]}), do: value
  defp unpin(value), do: value

  @doc false
  @spec to_interval(String.t() | {term(), term()}) :: String.t()
  def to_interval(interval) when is_binary(interval), do: interval
  def to_interval({start, stop}), do: interval_bound(start) <> "/" <> interval_bound(stop)

  defp interval_bound(value) when is_binary(value), do: value
  defp interval_bound(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp interval_bound(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp interval_bound(%Date{} = value), do: Date.to_iso8601(value)

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
end
