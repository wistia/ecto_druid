defmodule Ecto.Adapters.Druid.QueryTest do
  use ExUnit.Case

  import Ecto.Query
  use Ecto.Druid.Query

  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.Wikipedia

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  defp sql(query) do
    {sql, _params} = TestRepo.to_sql(query)
    sql
  end

  describe "type/2" do
    test "casts to Druid's SQL types" do
      assert sql(from(w in Wikipedia, select: type(w.added, :float))) =~
               ~s{SELECT CAST(w0."added" AS DOUBLE)}

      assert sql(from(w in Wikipedia, select: type(w.added, :decimal))) =~
               ~s{SELECT CAST(w0."added" AS DECIMAL)}

      assert sql(from(w in Wikipedia, select: type(w.added, :boolean))) =~
               ~s{SELECT CAST(w0."added" AS BOOLEAN)}

      assert sql(from(w in Wikipedia, select: type(w.added, :string))) =~
               ~s{SELECT CAST(w0."added" AS VARCHAR)}

      assert sql(from(w in Wikipedia, select: type(w.page, :integer))) =~
               ~s{SELECT CAST(w0."page" AS BIGINT)}

      assert sql(from(w in Wikipedia, select: type(w.time, :date))) =~
               ~s{SELECT CAST(w0."__time" AS DATE)}

      for type <- [:utc_datetime, :utc_datetime_usec, :naive_datetime, :naive_datetime_usec] do
        assert sql(from(w in Wikipedia, select: type(^~U[2026-01-01 00:00:00Z], ^type))) =~
                 ~s{SELECT CAST(? AS TIMESTAMP)}
      end
    end

    test "keeps the cast together inside arithmetic" do
      assert sql(from(w in Wikipedia, select: type(w.added, :float) / 2)) =~
               ~s{SELECT CAST(w0."added" AS DOUBLE) / 2}
    end

    test "raises for types Druid can't cast to" do
      assert_raise Ecto.QueryError, ~r/Druid can't cast to :map. Use parse_json/, fn ->
        sql(from(w in Wikipedia, select: type(w.page, :map)))
      end

      assert_raise Ecto.QueryError, ~r/Druid can't cast to :binary/, fn ->
        sql(from(w in Wikipedia, select: type(w.page, :binary)))
      end
    end
  end

  describe "string literals" do
    test "double single quotes" do
      assert sql(from(w in Wikipedia, where: w.page == "'t Suydevelt", select: w.page)) =~
               ~s{WHERE (w0."page" = '''t Suydevelt')}
    end

    test "leave backslashes alone, as Druid doesn't treat them as escapes" do
      assert sql(from(w in Wikipedia, where: regexp_like(w.page, "^\\d+$"), select: w.page)) =~
               ~S{WHERE (REGEXP_LIKE(w0."page", '^\d+$'))}
    end
  end

  describe "datetime_add/3" do
    # The unit has to be a literal, so there's a test per unit
    for {unit, interval} <- [
          {"year", "INTERVAL '1' YEAR"},
          {"month", "INTERVAL '1' MONTH"},
          {"week", "INTERVAL '7' DAY"},
          {"day", "INTERVAL '1' DAY"},
          {"hour", "INTERVAL '1' HOUR"},
          {"minute", "INTERVAL '1' MINUTE"},
          {"second", "INTERVAL '1' SECOND"},
          {"millisecond", "INTERVAL '0.001' SECOND"},
          {"microsecond", "INTERVAL '0.001' SECOND / 1000"}
        ] do
      test "writes #{unit} as an interval Druid handles" do
        assert sql(from(w in Wikipedia, select: datetime_add(w.time, 2, unquote(unit)))) =~
                 ~s{SELECT (w0."__time" + (2) * #{unquote(interval)})}
      end
    end

    test "adds a multiple of an interval to the datetime" do
      assert sql(from(w in Wikipedia, select: datetime_add(w.time, 1, "day"))) =~
               ~s{SELECT (w0."__time" + (1) * INTERVAL '1' DAY)}

      assert sql(from(w in Wikipedia, select: datetime_add(w.time, -2, "month"))) =~
               ~s{SELECT (w0."__time" + (-2) * INTERVAL '1' MONTH)}

      assert sql(from(w in Wikipedia, select: datetime_add(w.time, 1.5, "hour"))) =~
               ~s{SELECT (w0."__time" + (1.5) * INTERVAL '1' HOUR)}
    end

    test "keeps the datetime's parameter before the count's" do
      {sql, params} =
        TestRepo.to_sql(
          from(w in Wikipedia, select: datetime_add(^~N[2026-01-01 00:00:00], ^(-3), "day"))
        )

      assert sql =~ ~s{SELECT (? + (?) * INTERVAL '1' DAY)}
      assert params == [~N[2026-01-01 00:00:00], Decimal.new(-3)]
    end

    test "groups an expression count" do
      assert sql(from(w in Wikipedia, select: datetime_add(w.time, w.added + 1, "hour"))) =~
               ~s{SELECT (w0."__time" + (w0."added" + CAST(1 AS DECIMAL)) * INTERVAL '1' HOUR)}
    end

    test "ago/2 and from_now/2 subtract from and add to a pinned now" do
      {sql, [_now]} = TestRepo.to_sql(from(w in Wikipedia, where: w.time > ago(3, "day")))
      assert sql =~ ~s{WHERE (w0."__time" > (? + (-3) * INTERVAL '1' DAY))}

      assert sql(from(w in Wikipedia, where: w.time < from_now(2, "week"))) =~
               ~s{WHERE (w0."__time" < (? + (2) * INTERVAL '7' DAY))}
    end
  end

  describe "date_add/3" do
    test "casts the date so Druid can type a parameter" do
      assert sql(from(w in Wikipedia, where: w.time < date_add(^~D[2026-01-31], 1, "month"))) =~
               ~s{WHERE (w0."__time" < CAST((CAST(? AS DATE) + (1) * INTERVAL '1' MONTH) AS DATE))}
    end

    test "doesn't cast a date twice" do
      assert sql(from(w in Wikipedia, select: date_add(type(w.time, :date), 1, "month"))) =~
               ~s{SELECT CAST((CAST(w0."__time" AS DATE) + (1) * INTERVAL '1' MONTH) AS DATE)}
    end
  end

  describe "JSON paths" do
    test "read a scalar with JSON_VALUE and bracketed keys" do
      assert sql(from(w in "wikipedia", select: w.data["a"]["c d"][1])) =~
               ~s{SELECT JSON_VALUE(w0."data", '$[''a''][''c d''][1]')}
    end

    test "raise for a key with a single quote, which Druid can't address" do
      assert_raise Ecto.QueryError, ~r/can't contain a key with a single quote: "it's"/, fn ->
        sql(from(w in "wikipedia", select: w.data["it's"]))
      end
    end
  end

  describe "in" do
    test "a value in an array uses SCALAR_IN_ARRAY" do
      assert sql(from(w in "wikipedia", select: "a" in w.tags)) =~
               ~s{SELECT SCALAR_IN_ARRAY('a', w0."tags")}
    end

    test "a pinned list still expands into IN" do
      assert sql(from(w in Wikipedia, where: w.page in ^["a", "b"], select: w.page)) =~
               ~s{WHERE (w0."page" IN (?,?))}
    end
  end

  describe "values/2" do
    test "casts each column to a Druid type" do
      rows = [%{n: 1, t: ~U[2026-01-01 00:00:00Z], s: "x"}]
      types = %{n: :integer, t: :utc_datetime, s: :string}

      assert sql(from(v in values(rows, types), select: v)) =~
               ~s{ROW(CAST(? AS VARCHAR),CAST(? AS BIGINT),CAST(? AS TIMESTAMP))}
    end
  end
end
