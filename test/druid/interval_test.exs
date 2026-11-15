defmodule Druid.IntervalTest do
  use ExUnit.Case, async: true
  alias Druid.Interval

  doctest Druid.Interval

  describe "new/2" do
    test "formats DateTime, NaiveDateTime, Date and string bounds" do
      assert to_string(Interval.new(~N[2026-11-01 00:00:00], ~D[2026-11-08])) ==
               "2026-11-01T00:00:00/2026-11-08"

      assert to_string(Interval.new("2026-11-01", "2026-11-08")) == "2026-11-01/2026-11-08"
    end

    test "takes a period for either bound" do
      assert to_string(Interval.new(~D[2026-11-01], "P1M")) == "2026-11-01/P1M"

      assert to_string(Interval.new(~D[2026-11-01], year: 1, month: 2, hour: 3, second: 4)) ==
               "2026-11-01/P1Y2MT3H4S"

      assert to_string(Interval.new([minute: 30], ~U[2026-11-01 00:00:00Z])) ==
               "PT30M/2026-11-01T00:00:00Z"
    end

    test "takes a Duration as a period" do
      assert to_string(Interval.new(~D[2026-11-01], Duration.new!(day: 3))) == "2026-11-01/P3D"
    end

    test "rejects invalid bounds" do
      assert_raise ArgumentError, fn -> Interval.new(~D[2026-11-01], 5) end
      assert_raise ArgumentError, fn -> Interval.new(~D[2026-11-01], fortnight: 1) end
      assert_raise ArgumentError, fn -> Interval.new(~D[2026-11-01], day: 0) end
      assert_raise ArgumentError, fn -> Interval.new(~D[2026-11-01], day: 1.5) end
      assert_raise ArgumentError, fn -> Interval.new("P1D", day: 1) end
    end
  end

  describe "last/2" do
    test "ends at the given stop" do
      assert to_string(Interval.last([hour: 1], ~U[2026-11-15 12:00:00Z])) ==
               "PT1H/2026-11-15T12:00:00Z"
    end

    test "ends now by default" do
      %Interval{start: [day: 7], stop: %DateTime{} = stop} = Interval.last(day: 7)
      assert DateTime.diff(DateTime.utc_now(), stop) < 5
    end

    test "requires a period" do
      assert_raise ArgumentError, fn -> Interval.last(~D[2026-11-01]) end
    end
  end

  describe "to_iso8601/1" do
    test "takes tuples and strings" do
      assert Interval.to_iso8601({~D[2026-11-01], ~D[2026-11-02]}) == "2026-11-01/2026-11-02"
      assert Interval.to_iso8601("2026-11-01/P1D") == "2026-11-01/P1D"
    end
  end

  test "encodes to JSON as its string" do
    assert Jason.encode!(%{intervals: [Interval.new(~D[2026-11-01], day: 1)]}) ==
             ~s({"intervals":["2026-11-01/P1D"]})
  end
end
