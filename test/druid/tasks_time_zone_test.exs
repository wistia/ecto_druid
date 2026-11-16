defmodule Druid.TasksTimeZoneTest do
  # Swaps the global time zone database
  use ExUnit.Case, async: false

  # One zone, "Test/Eastern": UTC-4 until clocks fall back at 2026-11-01
  # 06:00 UTC (02:00 local), then UTC-5.
  defmodule FakeZones do
    @behaviour Calendar.TimeZoneDatabase

    @switch ~N[2026-11-01 06:00:00]
    @edt %{utc_offset: -5 * 3600, std_offset: 3600, zone_abbr: "EDT"}
    @est %{utc_offset: -5 * 3600, std_offset: 0, zone_abbr: "EST"}

    @impl true
    def time_zone_period_from_utc_iso_days(iso_days, "Test/Eastern") do
      {year, month, day, hour, minute, second, _} =
        Calendar.ISO.naive_datetime_from_iso_days(iso_days)

      utc = NaiveDateTime.new!(year, month, day, hour, minute, second)
      {:ok, if(NaiveDateTime.before?(utc, @switch), do: @edt, else: @est)}
    end

    def time_zone_period_from_utc_iso_days(_, _), do: {:error, :time_zone_not_found}

    @impl true
    def time_zone_periods_from_wall_datetime(wall, "Test/Eastern") do
      {:ok, if(NaiveDateTime.before?(wall, ~N[2026-11-01 01:00:00]), do: @edt, else: @est)}
    end

    def time_zone_periods_from_wall_datetime(_, _), do: {:error, :time_zone_not_found}
  end

  setup do
    previous = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(FakeZones)
    on_exit(fn -> Calendar.put_time_zone_database(previous) end)
  end

  test "days start at local midnight across a clock change" do
    intervals = Druid.Tasks.intervals(~D[2026-10-31], ~D[2026-11-03], time_zone: "Test/Eastern")

    assert Enum.map(intervals, &to_string/1) == [
             "2026-10-31T04:00:00Z/2026-11-01T04:00:00Z",
             # The day clocks fall back is 25 hours long
             "2026-11-01T04:00:00Z/2026-11-02T05:00:00Z",
             "2026-11-02T05:00:00Z/2026-11-03T05:00:00Z"
           ]

    # A local day spans two UTC days of input
    assert Druid.Tasks.partition_prefixes("b", hd(intervals), "%d") == ["b/31", "b/01"]
  end

  test "DateTime bounds are read in the time zone" do
    assert [interval] =
             Druid.Tasks.intervals(~U[2026-11-02 05:00:00Z], "2026-11-03",
               time_zone: "Test/Eastern"
             )

    assert to_string(interval) == "2026-11-02T05:00:00Z/2026-11-03T05:00:00Z"
  end
end
