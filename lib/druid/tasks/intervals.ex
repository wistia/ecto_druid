defmodule Druid.Tasks.Intervals do
  @moduledoc false
  # Splits a time range into backfill intervals, and lists the time-partitioned
  # storage prefixes an interval covers. See Druid.Tasks.intervals/3 and
  # Druid.Tasks.partition_prefixes/4.

  alias Ecto.Druid.Interval

  @units [:hour, :day, :week, :month]

  def split(from, to, opts) do
    time_zone = Keyword.get(opts, :time_zone, "Etc/UTC")
    {count, unit} = step!(Keyword.get(opts, :step, :day))

    start = to_local(from, time_zone, :from)
    stop = to_local(to, time_zone, :to)

    if NaiveDateTime.compare(start, stop) != :lt do
      raise ArgumentError,
            "expected from to be before to, got: #{inspect(from)} and #{inspect(to)}"
    end

    # Each boundary is measured from the start, so month steps from the 31st
    # don't drift to the 28th after February.
    0
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&advance(start, &1 * count, unit))
    |> Stream.take_while(&(NaiveDateTime.compare(&1, stop) == :lt))
    |> Enum.to_list()
    |> Kernel.++([stop])
    |> Enum.map(&to_utc(&1, time_zone))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> Interval.new(a, b) end)
  end

  def partition_prefixes(base, interval, format, opts) do
    {start, stop} = utc_bounds!(interval)
    step = Keyword.get_lazy(opts, :step, fn -> if format =~ "%H", do: :hour, else: :day end)

    unless step in [:hour, :day] do
      raise ArgumentError, "expected :step to be :hour or :day, got: #{inspect(step)}"
    end

    base = String.trim_trailing(base, "/")
    first = floor_to(start, step)
    seconds = if step == :hour, do: 3600, else: 86_400

    first
    |> Stream.iterate(&NaiveDateTime.add(&1, seconds))
    |> Stream.take_while(&(NaiveDateTime.compare(&1, stop) == :lt))
    |> Enum.map(&(base <> "/" <> Calendar.strftime(&1, format)))
  end

  defp step!(unit) when unit in @units, do: {1, unit}

  defp step!({count, unit}) when is_integer(count) and count > 0 and unit in @units,
    do: {count, unit}

  defp step!(step) do
    raise ArgumentError,
          "expected :step to be :hour, :day, :week, :month or a {count, unit} tuple, got: " <>
            inspect(step)
  end

  defp advance(naive, n, :hour), do: NaiveDateTime.add(naive, n * 3600)
  defp advance(naive, n, :day), do: shift_date(naive, &Date.add(&1, n))
  defp advance(naive, n, :week), do: shift_date(naive, &Date.add(&1, n * 7))
  defp advance(naive, n, :month), do: shift_date(naive, &add_months(&1, n))

  defp shift_date(naive, fun) do
    NaiveDateTime.new!(fun.(NaiveDateTime.to_date(naive)), NaiveDateTime.to_time(naive))
  end

  defp add_months(date, n) do
    months = date.year * 12 + date.month - 1 + n
    year = div(months, 12)
    month = rem(months, 12) + 1
    day = min(date.day, Calendar.ISO.days_in_month(year, month))
    Date.new!(year, month, day)
  end

  # Bounds become wall-clock times in the time zone, so that steps of a day or
  # more land on the same local time across daylight saving changes.
  defp to_local(%Date{} = date, _tz, _name), do: NaiveDateTime.new!(date, ~T[00:00:00])
  defp to_local(%NaiveDateTime{} = naive, _tz, _name), do: naive

  defp to_local(%DateTime{} = dt, tz, _name) do
    case DateTime.shift_zone(dt, tz) do
      {:ok, local} -> DateTime.to_naive(local)
      {:error, reason} -> raise ArgumentError, zone_error(tz, reason)
    end
  end

  defp to_local(string, tz, name) when is_binary(string) do
    with {:error, _} <- Date.from_iso8601(string),
         {:error, _} <- datetime_from_iso8601(string),
         {:error, _} <- NaiveDateTime.from_iso8601(string) do
      raise ArgumentError,
            "expected #{name} to be an ISO 8601 date or date-time, got: #{inspect(string)}"
    else
      {:ok, value} -> to_local(value, tz, name)
    end
  end

  defp to_local(other, _tz, name) do
    raise ArgumentError,
          "expected #{name} to be a Date, DateTime, NaiveDateTime or ISO 8601 string, got: " <>
            inspect(other)
  end

  defp datetime_from_iso8601(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _offset} -> {:ok, dt}
      error -> error
    end
  end

  defp to_utc(naive, "Etc/UTC"), do: DateTime.from_naive!(naive, "Etc/UTC")

  defp to_utc(naive, tz) do
    case DateTime.from_naive(naive, tz) do
      {:ok, dt} -> utc_datetime(dt)
      # The wall-clock time was skipped or repeated by a clock change
      {:gap, _before, after_gap} -> utc_datetime(after_gap)
      {:ambiguous, first, _second} -> utc_datetime(first)
      {:error, reason} -> raise ArgumentError, zone_error(tz, reason)
    end
  end

  # Converting to UTC needs no time zone database
  defp utc_datetime(dt) do
    utc = dt |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)
    %{utc | microsecond: dt.microsecond}
  end

  defp zone_error(tz, :utc_only_time_zone_database) do
    "time zone #{inspect(tz)} needs a time zone database. Add one such as :tz or :tzdata " <>
      "and set it with `config :elixir, :time_zone_database, ...`"
  end

  defp zone_error(tz, reason), do: "invalid time zone #{inspect(tz)}: #{inspect(reason)}"

  defp utc_bounds!(%Interval{start: start, stop: stop}), do: {utc!(start), utc!(stop)}

  defp utc_bounds!(string) when is_binary(string) do
    case String.split(string, "/") do
      [start, stop] -> {utc!(start), utc!(stop)}
      _ -> raise ArgumentError, "expected an interval, got: #{inspect(string)}"
    end
  end

  defp utc!(%DateTime{} = dt), do: dt |> utc_datetime() |> DateTime.to_naive()
  defp utc!(%NaiveDateTime{} = naive), do: naive
  defp utc!(%Date{} = date), do: NaiveDateTime.new!(date, ~T[00:00:00])

  defp utc!(string) when is_binary(string) do
    with {:error, _} <- datetime_from_iso8601(string),
         {:error, _} <- NaiveDateTime.from_iso8601(string),
         {:error, _} <- Date.from_iso8601(string) do
      raise ArgumentError,
            "partition_prefixes needs an interval with date or date-time bounds, got: " <>
              inspect(string)
    else
      {:ok, value} -> utc!(value)
    end
  end

  defp utc!(other) do
    raise ArgumentError,
          "partition_prefixes needs an interval with date or date-time bounds, got: " <>
            inspect(other)
  end

  defp floor_to(naive, :hour), do: %{naive | minute: 0, second: 0, microsecond: {0, 0}}
  defp floor_to(naive, :day), do: NaiveDateTime.new!(NaiveDateTime.to_date(naive), ~T[00:00:00])
end
