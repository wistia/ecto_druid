defmodule Ecto.Adapters.DruidTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid

  describe "checkout/1" do
    test "proxies to fun" do
      assert Druid.checkout(:meta, :opts, fn -> :ok end) == :ok
    end
  end

  describe "checked_out?/1" do
    test "returns false" do
      assert Druid.checked_out?(:meta) == false
    end
  end

  describe "dumpers/2" do
    test "dumps custom types through the custom type" do
      assert Ecto.Type.adapter_dump(Druid, Ecto.Druid.DateTime, ~U[2016-06-27 00:00:00Z]) ==
               {:ok, "2016-06-27T00:00:00Z"}
    end
  end

  describe "Types.to_db/1" do
    alias Ecto.Adapters.Druid.Types

    test "tags params with Avatica SQL types" do
      assert Types.to_db(1) == %{type: "BIGINT", value: 1}
      assert Types.to_db(1.5) == %{type: "DOUBLE", value: 1.5}
      assert Types.to_db("a") == %{type: "VARCHAR", value: "a"}
      assert Types.to_db(true) == %{type: "BOOLEAN", value: true}
    end

    test "sends datetimes as ISO8601 timestamps" do
      assert Types.to_db(~U[2016-06-27 00:00:00Z]) ==
               %{type: "TIMESTAMP", value: "2016-06-27T00:00:00Z"}

      assert Types.to_db(~N[2016-06-27 00:00:00]) ==
               %{type: "TIMESTAMP", value: "2016-06-27T00:00:00"}
    end

    test "sends dates, nil and lists" do
      assert Types.to_db(~D[2016-06-27]) == %{type: "DATE", value: "2016-06-27"}
      assert Types.to_db(nil) == %{type: "NULL", value: nil}
      assert Types.to_db(["a", "b"]) == %{type: "ARRAY", value: ["a", "b"]}
    end

    # Druid reads a TIMESTAMP parameter as a wall-clock time in sqlTimeZone,
    # whatever offset it has
    test "sends datetimes as their wall-clock time in sqlTimeZone" do
      dt = ~U[2024-01-01 05:00:00Z]

      for zone <- ["EST", "-05:00", "-0500", "-05", "Etc/GMT+5"] do
        assert Types.to_db_params([dt], %{sqlTimeZone: zone}) ==
                 [%{type: "TIMESTAMP", value: "2024-01-01T00:00:00"}],
               zone
      end

      assert Types.to_db_params([dt], %{"sqlTimeZone" => "+09:30"}) ==
               [%{type: "TIMESTAMP", value: "2024-01-01T14:30:00"}]

      assert Types.to_db_params([[dt]], %{sqlTimeZone: "EST"}) ==
               [%{type: "ARRAY", value: ["2024-01-01T00:00:00"]}]
    end

    test "leaves params alone without a non-UTC sqlTimeZone" do
      params = [~U[2024-01-01 05:00:00.123Z], ~N[2024-01-01 05:00:00], ~D[2024-01-01]]

      expected = [
        %{type: "TIMESTAMP", value: "2024-01-01T05:00:00.123Z"},
        %{type: "TIMESTAMP", value: "2024-01-01T05:00:00"},
        %{type: "DATE", value: "2024-01-01"}
      ]

      assert Types.to_db_params(params, %{}) == expected
      assert Types.to_db_params(params, %{sqlTimeZone: "Etc/UTC"}) == expected

      assert Types.to_db_params(tl(params), %{sqlTimeZone: "EST"}) ==
               [
                 %{type: "TIMESTAMP", value: "2024-01-01T05:00:00"},
                 %{type: "DATE", value: "2024-01-01"}
               ]
    end

    test "needs a time zone database for zones that aren't a fixed offset" do
      assert_raise ArgumentError, ~r/needs a time zone database/, fn ->
        Types.to_db_params([~U[2024-01-01 05:00:00Z]], %{sqlTimeZone: "America/New_York"})
      end
    end

    # Druid rejects a DECIMAL parameter sent as a JSON string
    test "sends decimals as JSON numbers" do
      assert %{type: "DECIMAL", value: value} = Types.to_db(Decimal.new("-1.50"))
      assert Jason.encode!(value) == "-1.50"
    end
  end

  describe "loading Druid's ISO 8601 strings" do
    defp load(type, value) do
      Ecto.Type.adapter_load(Druid, type, value)
    end

    test "into dates and datetimes" do
      assert load(:date, "2016-06-27T00:00:00.000Z") == {:ok, ~D[2016-06-27]}
      assert load(:utc_datetime, "2016-06-27T01:02:03.000Z") == {:ok, ~U[2016-06-27 01:02:03Z]}

      assert load(:utc_datetime_usec, "2016-06-27T01:02:03.004Z") ==
               {:ok, ~U[2016-06-27 01:02:03.004000Z]}

      assert load(:naive_datetime, "2016-06-27T01:02:03.000Z") ==
               {:ok, ~N[2016-06-27 01:02:03]}

      assert load(:naive_datetime_usec, "2016-06-27T01:02:03.004Z") ==
               {:ok, ~N[2016-06-27 01:02:03.004000]}
    end

    # With a sqlTimeZone, Druid returns values with that zone's offset
    test "keeps the wall-clock time in the query's time zone for dates and naive datetimes" do
      assert load(:date, "2024-01-01T00:00:00.000+09:00") == {:ok, ~D[2024-01-01]}
      assert load(:date, "2024-01-01T00:00:00.000-05:00") == {:ok, ~D[2024-01-01]}

      assert load(:naive_datetime, "2024-01-01T00:00:00.000-05:00") ==
               {:ok, ~N[2024-01-01 00:00:00]}

      assert load(:utc_datetime, "2024-01-01T00:00:00.000-05:00") ==
               {:ok, ~U[2024-01-01 05:00:00Z]}
    end

    test "passes nil through and rejects other strings" do
      assert load(:date, nil) == {:ok, nil}
      assert load(:utc_datetime, "yesterday") == :error
    end
  end

  describe "merge_context/2" do
    test "uses the repo config context by default" do
      opts = Druid.merge_context([context: %{sqlTimeZone: "America/New_York"}], [])
      assert opts[:context] == %{sqlTimeZone: "America/New_York"}
    end

    test "per-call context overrides repo config context" do
      opts =
        Druid.merge_context(
          [context: %{sqlTimeZone: "America/New_York", timeout: 1000}],
          context: %{sqlTimeZone: "UTC"}
        )

      assert opts[:context] == %{sqlTimeZone: "UTC", timeout: 1000}
    end

    test "defaults to an empty context" do
      assert Druid.merge_context([], [])[:context] == %{}
    end
  end
end
