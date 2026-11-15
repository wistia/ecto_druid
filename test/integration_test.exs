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

    assert TestRepo.native_query(query) == [
             %{
               "result" => %{"added" => 11_774_265, "deleted" => 278_288},
               "timestamp" => "2016-06-27T00:00:00.000Z"
             }
           ]
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

    test "a Druid.Interval in time_in_interval" do
      use Ecto.Druid.Query

      interval = Druid.Interval.new(~D[2016-06-27], day: 1)

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
  end
end
