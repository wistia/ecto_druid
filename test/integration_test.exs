defmodule IntegrationTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.Wikipedia

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  test "queries single druid result" do
    assert TestRepo.one(Wikipedia.by_page("Black Dahlia")) ==
             %{
               added: 3,
               deleted: 0,
               delta: 3,
               unique_users: 1,
               delta_histogram: [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
               ds_theta: "AQMDAAA6zJOFHZZiGEjVRw=="
             }
  end

  test "queries timeseries druid result" do
    assert TestRepo.all(Wikipedia.over_time("1947-01-01T00:00:00Z/2040-12-31T23:59:59Z")) == [
             %{
               time: ~U[2016-06-27 00:00:00.000Z],
               added: 1848,
               deleted: 0,
               delta: 1848,
               unique_users: 2,
               delta_histogram: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0],
               ds_theta: "AgMDAAAazJMCAAAAAACAPzd6/yEG3wQlidpvB7iALXo=",
               page: "'t Suydevelt"
             },
             %{
               time: ~U[2016-06-27 00:00:00.000Z],
               added: 39,
               deleted: 0,
               delta: 39,
               unique_users: 1,
               delta_histogram: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
               ds_theta: "AQMDAAA6zJPn1y+tXohAAQ==",
               page: "(1094) Siberia"
             },
             %{
               time: ~U[2016-06-27 00:00:00.000Z],
               added: 0,
               deleted: 0,
               delta: 0,
               unique_users: 1,
               delta_histogram: [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
               ds_theta: "AQMDAAA6zJOyxVBz8PCTLw==",
               page: "(2383) Bradley"
             }
           ]
  end

  test "native query" do
    query = %{
      queryType: "timeseries",
      dataSource: "wikipedia",
      granularity: "all",
      intervals: [
        "2013-01-01/2048-01-02"
      ],
      aggregations: [
        %{type: "longSum", name: "added", fieldName: "added"},
        %{type: "longSum", name: "deleted", fieldName: "deleted"}
      ],
      limit: 3
    }

    assert TestRepo.native_query!(query) == [
             %{
               "__time" => "2016-06-27T00:00:00.000Z",
               "added" => 11_774_265,
               "deleted" => 278_288
             }
           ]

    assert TestRepo.native_query!(query, raw: true) == [
             %{
               "result" => %{"added" => 11_774_265, "deleted" => 278_288},
               "timestamp" => "2016-06-27T00:00:00.000Z"
             }
           ]
  end

  test "to_native returns the native query Druid plans" do
    native = TestRepo.to_native(Wikipedia.by_page("Black Dahlia"))

    assert native["queryType"] == "timeseries"
    assert native["dataSource"] == %{"type" => "table", "name" => "wikipedia"}
    refute Map.has_key?(native["context"], "sqlQueryId")

    # The planned query runs as is
    assert [%{"a0" => 3}] = TestRepo.native_query!(native)
  end

  test "native query rows" do
    query = %{
      queryType: "topN",
      dataSource: "wikipedia",
      intervals: ["2016-06-27/2016-06-28"],
      granularity: "all",
      dimension: "channel",
      metric: "edits",
      threshold: 2,
      aggregations: [%{type: "count", name: "edits"}]
    }

    assert [%{"__time" => "2016-06-27T00:00:00.000Z", "channel" => _, "edits" => _} | _] =
             query |> TestRepo.native_query!(raw: true) |> Ecto.Druid.Native.rows(query)
  end

  test "native query builders" do
    import Ecto.Druid.Native.Expression
    import Ecto.Druid.Native.Filter
    import Ecto.Druid.Native.Aggregator
    import Ecto.Druid.Native.PostAggregator, only: [arithmetic: 3]
    alias Ecto.Druid.Native

    page = "Black Dahlia"

    query = %{
      queryType: "groupBy",
      dataSource: "wikipedia",
      intervals: [Ecto.Druid.Interval.new(~D[2016-06-27], day: 1)],
      granularity: "all",
      virtualColumns: [Native.virtual_column("net", expr(added - deleted), "LONG")],
      dimensions: [Native.dimension("page", name: "title")],
      filter:
        and_([
          equals("page", page),
          range("__time", lower: ~U[2016-06-27 00:00:00Z]),
          null("user") |> not_(),
          expression(expr(page == ^page and added >= 0)),
          nil
        ]),
      aggregations: [
        count("edits"),
        long_sum("net"),
        long_sum(expr(added * 2), name: "doubled"),
        count("robot_edits") |> filtered(equals("isRobot", "true")),
        string_any("channel", max_string_bytes: 64),
        theta_sketch("user", name: "users")
      ],
      postAggregations: [arithmetic("net_per_edit", :/, ["net", "edits"])]
    }

    assert [
             %{
               "title" => "Black Dahlia",
               "edits" => 1,
               "net" => 3,
               "doubled" => 6,
               "robot_edits" => 0,
               "channel" => "#en.wikipedia",
               "users" => 1.0,
               "net_per_edit" => 3.0
             }
           ] = TestRepo.native_query!(query)
  end

  test "native queries on a schema, with checked columns and the repo context" do
    query = %{
      queryType: "timeseries",
      dataSource: Wikipedia,
      intervals: ["2016-06-27/2016-06-28"],
      granularity: "all",
      filter: %{
        type: "equals",
        column: "page",
        matchValueType: "STRING",
        matchValue: "Black Dahlia"
      },
      aggregations: [%{type: "longSum", name: "added", fieldName: "added"}]
    }

    assert {:ok, [%{"added" => 3}]} =
             TestRepo.native_query(query, merge_context: true)

    assert_raise ArgumentError, ~r/doesn't define: \["nope"\]/, fn ->
      TestRepo.native_query(%{query | filter: Ecto.Druid.Native.Filter.null("nope")})
    end

    import Ecto.Druid.Native.Expression

    assert {:ok, [%{"net" => 3}]} =
             TestRepo.native_query(%{
               query
               | aggregations: [
                   %{type: "longSum", name: "net", expression: expr(added - deleted)}
                 ]
             })

    assert_raise ArgumentError, ~r/doesn't define: \["nope"\]/, fn ->
      TestRepo.native_query(%{
        query
        | filter: Ecto.Druid.Native.Filter.expression(expr(nope > 0))
      })
    end
  end

  test "native query errors carry the queryId" do
    query = %{queryType: "timeseries", dataSource: "no_such_source", intervals: ["2016/2017"]}

    assert {:error, %Ecto.Adapters.Druid.NativeQueryError{query_id: id, reason: reason}} =
             TestRepo.native_query(query)

    assert {:ok, _} = Ecto.UUID.cast(id)
    assert %Druid.Client.RequestError{} = reason
  end

  # The queries below take several seconds: they pair every edit with every
  # other edit by a robot, or by a human. Their requests give up after two
  # seconds, long enough for the Broker to have started the query, so it is
  # still running when it is canceled. With a shorter timeout, a busy Broker
  # may not have started the query before the client hangs up, and then never
  # runs it, leaving nothing to cancel.
  @slow_timeout 2_000

  test "native queries that time out are canceled" do
    robots = %{
      queryType: "scan",
      dataSource: "wikipedia",
      intervals: ["2016-06-27/2016-06-28"],
      columns: ["isRobot"],
      resultFormat: "compactedList"
    }

    query = %{
      queryType: "timeseries",
      dataSource: %{
        type: "join",
        left: "wikipedia",
        right: %{type: "query", query: robots},
        rightPrefix: "r.",
        condition: ~s(isRobot == "r.isRobot"),
        joinType: "INNER"
      },
      intervals: ["2016-06-27/2016-06-28"],
      granularity: "all",
      aggregations: [%{type: "count", name: "pairs"}]
    }

    assert {:error, %Ecto.Adapters.Druid.NativeQueryError{canceled: true} = error} =
             TestRepo.native_query(query, receive_timeout: @slow_timeout)

    assert %Req.TransportError{reason: :timeout} = error.reason
  end

  def send_request(_event, _measurements, metadata, test) do
    send(test, {:request, metadata.method, metadata.status})
  end

  test "SQL queries that time out are canceled" do
    import Ecto.Query

    test = self()
    handler = "sql-timeout-#{inspect(test)}"

    :telemetry.attach(handler, [:druid, :request, :stop], &__MODULE__.send_request/4, test)

    on_exit(fn -> :telemetry.detach(handler) end)

    robots = from(w in "wikipedia", select: %{is_robot: field(w, :isRobot)})

    query =
      from(w in "wikipedia",
        join: r in subquery(robots),
        on: field(w, :isRobot) == r.is_robot,
        select: count()
      )

    assert_raise Req.TransportError, ~r/timeout/, fn ->
      TestRepo.all(query, receive_timeout: @slow_timeout)
    end

    assert_received {:request, :delete, 202}
  end

  test "legacy native filters match the newer ones" do
    import Ecto.Druid.Native.Filter
    import Ecto.Druid.Native.Aggregator, only: [count: 1]

    count = fn filter ->
      [%{"edits" => edits}] =
        TestRepo.native_query!(%{
          queryType: "timeseries",
          dataSource: "wikipedia",
          intervals: ["2016-06-27/2016-06-28"],
          granularity: "all",
          filter: filter,
          aggregations: [count("edits")]
        })

      edits
    end

    assert count.(selector("channel", "#en.wikipedia")) ==
             count.(equals("channel", "#en.wikipedia"))

    assert count.(selector("channel", "#en.wikipedia")) == 6650

    assert count.(bound("added", lower: 10, lower_strict: true)) ==
             count.(range("added", lower: 10, lower_open: true))

    assert count.(bound("added", lower: 10, upper: 100)) ==
             count.(range("added", lower: 10, upper: 100))

    assert count.(selector("cityName", nil)) == count.(null("cityName"))
  end

  test "queries with hll sketch aggregations" do
    assert %{unique_users: 1, hll: hll} = TestRepo.one(Wikipedia.hll_by_page("Black Dahlia"))
    assert is_binary(hll)
  end

  test "queries with window functions" do
    assert TestRepo.all(Wikipedia.page_rankings()) ==
             [
               %{page: "'t Suydevelt", rank: 1},
               %{page: "(1094) Siberia", rank: 2},
               %{page: "(2383) Bradley", rank: 3}
             ]
  end

  test "queries with unnest" do
    import Ecto.Query
    import Ecto.Druid.Query.Table, only: [unnest: 2]
    import Ecto.Druid.Query.Array, only: [array: 1]

    query =
      from(t in "wikipedia",
        cross_join: u in unnest(array([1, 2, 3]), :n),
        where: t.page == "Black Dahlia",
        group_by: u.n,
        order_by: u.n,
        select: u.n
      )

    assert TestRepo.all(query) == [1, 2, 3]
  end

  test "queries with a custom sql query context" do
    assert %{added: 3} =
             TestRepo.one(Wikipedia.by_page("Black Dahlia"), context: %{sqlTimeZone: "Etc/UTC"})
  end

  describe "pinned params" do
    import Ecto.Query

    test "integers" do
      query =
        from(w in "wikipedia",
          where: w.page == "Black Dahlia" and w.added > ^2,
          select: w.added
        )

      assert TestRepo.all(query) == [3]
      assert TestRepo.all(from(w in query, where: w.added > ^3)) == []
    end

    test "DateTimes on a schema field" do
      count = fn dt ->
        TestRepo.one(from(w in Wikipedia, where: w.time < ^dt, select: count()))
      end

      assert count.(~U[2016-06-27 00:00:00.001Z]) == 24433
      assert count.(~U[2016-06-27 00:00:00Z]) == 0
    end

    test "DateTimes in a time_in_interval tuple" do
      use Ecto.Druid.Query

      count = fn start, stop ->
        TestRepo.one(
          from(w in Wikipedia, where: time_in_interval(w.time, {^start, ^stop}), select: count())
        )
      end

      assert count.(~U[2016-06-27 00:00:00Z], ~U[2016-06-28 00:00:00Z]) == 24433
      assert count.(~U[2016-06-26 00:00:00Z], ~U[2016-06-27 00:00:00Z]) == 0

      assert TestRepo.one(
               from(w in Wikipedia,
                 where: time_in_interval(w.time, {~D[2016-06-27], ~D[2016-06-28]}),
                 select: count()
               )
             ) == 24433

      interval = {~U[2016-06-27 00:00:00Z], ~U[2016-06-28 00:00:00Z]}

      assert TestRepo.one(
               from(w in "wikipedia",
                 where: time_in_interval(w.__time, ^interval),
                 select: count()
               )
             ) == 24433
    end

    test "a Ecto.Druid.Interval in time_in_interval" do
      use Ecto.Druid.Query

      interval = Ecto.Druid.Interval.new(~D[2016-06-27], day: 1)

      assert TestRepo.one(
               from(w in Wikipedia, where: time_in_interval(w.time, ^interval), select: count())
             ) == 24433
    end

    test "DateTimes on a schemaless field" do
      count = fn dt ->
        TestRepo.one(from(w in "wikipedia", where: w.__time < ^dt, select: count()))
      end

      assert count.(~U[2016-06-27 00:00:00.001Z]) == 24433
      assert count.(~U[2016-06-27 00:00:00Z]) == 0
    end

    test "Dates, Decimals and nil" do
      count = fn query -> TestRepo.one(from(w in query, select: count())) end

      assert count.(from(w in "wikipedia", where: w.__time >= ^~D[2016-06-27])) == 24433
      assert count.(from(w in "wikipedia", where: w.__time > ^~D[2016-06-27])) == 0
      assert count.(from(w in "wikipedia", where: w.added > ^Decimal.new("1.5"))) == 12705

      default = nil

      assert TestRepo.all(
               from(w in Wikipedia,
                 where: w.page == "Black Dahlia",
                 select: coalesce(w.page, ^default)
               )
             ) == ["Black Dahlia"]
    end
  end

  describe "Ecto expressions" do
    import Ecto.Query
    use Ecto.Druid.Query

    test "type/2" do
      assert TestRepo.one(
               from(w in Wikipedia,
                 where: w.page == "Black Dahlia",
                 select: {
                   type(w.added, :float) / 2,
                   type(w.added, :decimal) * 2,
                   type(w.added, :boolean),
                   type(w.delta * 100_000, :string),
                   type(w.time, :date),
                   type(^~U[2026-01-01 00:00:00Z], :utc_datetime)
                 }
               )
             ) == {1.5, 6.0, true, "300000", ~D[2016-06-27], ~U[2026-01-01 00:00:00Z]}
    end

    test "string literals with backslashes and quotes" do
      count = fn query -> TestRepo.one(from(w in query, select: count())) end

      assert count.(from(w in Wikipedia, where: regexp_like(w.page, "^\\d+$"))) == 28
      assert count.(from(w in Wikipedia, where: regexp_like(w.page, ^"^\\d+$"))) == 28
      assert count.(from(w in Wikipedia, where: w.page == "'t Suydevelt")) == 2
    end

    test "datetime_add/3, date_add/3, ago/2 and from_now/2" do
      assert TestRepo.one(
               from(w in Wikipedia,
                 where: w.page == "Black Dahlia",
                 select: {
                   datetime_add(w.time, 1, "day"),
                   datetime_add(w.time, -2, "week"),
                   datetime_add(w.time, ^1, "month"),
                   datetime_add(w.time, 1.5, "day"),
                   datetime_add(w.time, 5, "millisecond"),
                   datetime_add(w.time, 5000, "microsecond"),
                   datetime_add(^~N[2026-01-01 00:00:00], ^(-3), "day"),
                   date_add(type(w.time, :date), 1, "month")
                 }
               )
             ) ==
               {~U[2016-06-28 00:00:00.000Z], ~U[2016-06-13 00:00:00.000Z],
                ~U[2016-07-27 00:00:00.000Z], ~U[2016-06-28 12:00:00.000Z],
                ~U[2016-06-27 00:00:00.005Z], ~U[2016-06-27 00:00:00.005Z],
                ~N[2025-12-29 00:00:00], ~D[2016-07-27]}

      count = fn query -> TestRepo.one(from(w in query, select: count())) end

      assert count.(from(w in Wikipedia, where: w.time > ago(^20, "year"))) == 24433
      assert count.(from(w in Wikipedia, where: w.time > ago(1, "day"))) == 0
      assert count.(from(w in Wikipedia, where: w.time < from_now(1, "day"))) == 24433

      assert count.(from(w in Wikipedia, where: w.time <= date_add(^~D[2016-05-27], 1, "month"))) ==
               24433
    end

    test "JSON paths and a value in an array" do
      data =
        from(w in "wikipedia",
          where: w.page == "Black Dahlia",
          select: %{
            data: parse_json(~s({"a":{"b":1,"c d":[5,6],"x.y":"z"}})),
            tags: fragment("ARRAY['a','b']")
          }
        )

      assert TestRepo.one(
               from(d in subquery(data),
                 where: d.data["a"]["x.y"] == "z",
                 select: {d.data["a"]["b"], d.data["a"]["c d"][1], "a" in d.tags, "q" in d.tags}
               )
             ) == {"1", "6", true, false}
    end

    test "values/2" do
      rows = [%{n: 1, t: ~U[2026-01-01 00:00:00Z], s: "x"}]
      types = %{n: :integer, t: :utc_datetime, s: :string}

      assert TestRepo.all(from(v in values(rows, types), select: v)) == [
               %{n: 1, t: ~U[2026-01-01 00:00:00Z], s: "x"}
             ]
    end
  end
end
