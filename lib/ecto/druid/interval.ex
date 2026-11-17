defmodule Ecto.Druid.Interval do
  @moduledoc """
  An ISO 8601 time interval, for filtering on `__time` in Druid SQL and native
  queries.

  Each bound is a `DateTime`, `NaiveDateTime`, `Date` or ISO 8601 string. One
  bound (not both) may instead be a period: a `Duration`, a keyword list of
  `Duration`-style units (`:year`, `:month`, `:week`, `:day`, `:hour`,
  `:minute`, `:second`), or an ISO 8601 period string such as `"P1D"`. As in
  Druid, the start is inclusive and the stop is exclusive.

      iex> Ecto.Druid.Interval.new(~U[2026-11-01 00:00:00Z], ~U[2026-11-08 00:00:00Z]) |> to_string()
      "2026-11-01T00:00:00Z/2026-11-08T00:00:00Z"

      iex> Ecto.Druid.Interval.new(~D[2026-11-01], week: 1) |> to_string()
      "2026-11-01/P1W"

      iex> Ecto.Druid.Interval.new([day: 1, hour: 12], ~D[2026-11-08]) |> to_string()
      "P1DT12H/2026-11-08"

  ## SQL

  Pin an interval in `Ecto.Druid.Query.DateTime.time_in_interval/2`:

      interval = Ecto.Druid.Interval.last(day: 7)

      from p in "page_views", where: time_in_interval(p.__time, ^interval)

  ## Native queries

  Intervals encode to JSON as their ISO 8601 string, so they can go straight
  into a native query's `intervals`:

      MyApp.DruidRepo.native_query!(%{
        queryType: "timeseries",
        dataSource: "page_views",
        intervals: [Ecto.Druid.Interval.last(day: 7)],
        granularity: "day",
        aggregations: [%{type: "count", name: "rows"}]
      })

  They also implement `String.Chars`, so they work anywhere the client takes
  an interval string, such as `Druid.Client.DataSource.kill/2`.
  """

  @enforce_keys [:start, :stop]
  defstruct [:start, :stop]

  @typedoc "A `Duration`, a keyword list of `Duration`-style units, or an ISO 8601 period string."
  @type period :: struct() | Keyword.t() | String.t()
  @type bound :: DateTime.t() | NaiveDateTime.t() | Date.t() | String.t() | period()
  @type t :: %__MODULE__{start: bound(), stop: bound()}

  @date_units [year: "Y", month: "M", week: "W", day: "D"]
  @time_units [hour: "H", minute: "M", second: "S"]

  @doc """
  Builds an interval from `start` (inclusive) to `stop` (exclusive).

  Either bound may be a period, measured from the other bound. Raises
  `ArgumentError` if a bound isn't a supported value or both are periods.
  """
  @spec new(bound(), bound()) :: t()
  def new(start, stop) do
    if period?(start) and period?(stop) do
      raise ArgumentError, "an interval can't have a period for both bounds"
    end

    interval = %__MODULE__{start: start, stop: stop}
    # Validate the bounds now, rather than when the query runs.
    _ = to_iso8601(interval)
    interval
  end

  @doc """
  Builds an interval covering `period` up to `stop`, which defaults to now
  (`DateTime.utc_now/0`).

      Ecto.Druid.Interval.last(day: 7)
      Ecto.Druid.Interval.last("PT1H", ~U[2026-11-15 12:00:00Z])
  """
  @spec last(period(), DateTime.t() | NaiveDateTime.t() | Date.t() | String.t()) :: t()
  def last(period, stop \\ DateTime.utc_now()) do
    unless period?(period), do: raise(ArgumentError, "expected a period, got: #{inspect(period)}")
    new(period, stop)
  end

  @doc """
  Formats an interval as an ISO 8601 interval string, such as
  `"2026-11-01T00:00:00Z/2026-11-08T00:00:00Z"`.

  Also takes a `{start, stop}` tuple, with the same bounds as `new/2`, or an
  interval string, which is returned as is.
  """
  @spec to_iso8601(t() | {bound(), bound()} | String.t()) :: String.t()
  def to_iso8601(%__MODULE__{start: start, stop: stop}),
    do: bound_to_iso8601(start) <> "/" <> bound_to_iso8601(stop)

  def to_iso8601({start, stop}), do: start |> new(stop) |> to_iso8601()
  def to_iso8601(interval) when is_binary(interval), do: interval

  def to_iso8601(other) do
    raise ArgumentError,
          "expected a Ecto.Druid.Interval, {start, stop} tuple or interval string, got: #{inspect(other)}"
  end

  defp bound_to_iso8601(bound) when is_binary(bound), do: bound

  defp bound_to_iso8601(%module{} = bound) when module in [DateTime, NaiveDateTime, Date],
    do: module.to_iso8601(bound)

  # `Duration` is new in Elixir 1.17, so avoid referring to it at compile time.
  defp bound_to_iso8601(%{__struct__: Duration} = duration),
    do: apply(Duration, :to_iso8601, [duration])

  defp bound_to_iso8601([{_, _} | _] = period) do
    {time, date} = Keyword.split(period, Keyword.keys(@time_units))

    unless Keyword.keys(date) -- Keyword.keys(@date_units) == [] do
      raise ArgumentError, "invalid period: #{inspect(period)}"
    end

    date = period_part(@date_units, date)
    time = period_part(@time_units, time)

    case {date, time} do
      {"", ""} -> raise ArgumentError, "invalid period: #{inspect(period)}"
      {date, ""} -> "P" <> date
      {date, time} -> "P" <> date <> "T" <> time
    end
  end

  defp bound_to_iso8601(bound) do
    raise ArgumentError, "invalid interval bound: #{inspect(bound)}"
  end

  defp period_part(units, values) do
    for {unit, designator} <- units, value = values[unit], value != 0, into: "" do
      unless is_integer(value), do: raise(ArgumentError, "invalid period: #{inspect(values)}")
      "#{value}#{designator}"
    end
  end

  defp period?(%{__struct__: Duration}), do: true
  defp period?([{_, _} | _]), do: true
  defp period?("P" <> _), do: true
  defp period?(_), do: false

  defimpl String.Chars do
    def to_string(interval), do: Ecto.Druid.Interval.to_iso8601(interval)
  end

  defimpl Jason.Encoder do
    def encode(interval, opts) do
      interval |> Ecto.Druid.Interval.to_iso8601() |> Jason.Encode.string(opts)
    end
  end
end
