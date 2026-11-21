defmodule Ecto.Druid.NativeTest do
  use ExUnit.Case, async: true
  alias Ecto.Druid.Native

  doctest Ecto.Druid.Native

  @count %{type: "count", name: "rows"}
  @doubled %{type: "expression", name: "doubled", expression: "rows * 2"}

  describe "rows/3" do
    test "flattens each topN bucket" do
      query = %{"queryType" => "topN", "dimension" => "page", "aggregations" => [@count]}

      results = [
        %{
          "timestamp" => "2016-06-27T00:00:00.000Z",
          "result" => [%{"page" => "a", "rows" => 2}, %{"page" => "b", "rows" => 1}]
        },
        %{"timestamp" => "2016-06-28T00:00:00.000Z", "result" => [%{"page" => "c", "rows" => 3}]}
      ]

      assert Native.rows(results, query) == [
               %{"__time" => "2016-06-27T00:00:00.000Z", "page" => "a", "rows" => 2},
               %{"__time" => "2016-06-27T00:00:00.000Z", "page" => "b", "rows" => 1},
               %{"__time" => "2016-06-28T00:00:00.000Z", "page" => "c", "rows" => 3}
             ]
    end

    test "unwraps groupBy events, with the timestamp unless the granularity is all" do
      results = [
        %{"version" => "v1", "timestamp" => "2016-06-27T00:00:00.000Z", "event" => %{"rows" => 1}}
      ]

      for granularity <- ["all", %{type: "all"}, nil] do
        query = %{queryType: "groupBy", granularity: granularity}
        assert Native.rows(results, query) == [%{"rows" => 1}]
      end

      query = %{queryType: "groupBy", granularity: %{type: "period", period: "P1D"}}

      assert Native.rows(results, query) == [
               %{"__time" => "2016-06-27T00:00:00.000Z", "rows" => 1}
             ]
    end

    test "names groupBy array results in Druid's column order" do
      query = %{
        queryType: "groupBy",
        granularity: "day",
        dimensions: ["channel", %{type: "default", dimension: "page", outputName: "p"}],
        aggregations: [@count],
        postAggregations: [@doubled],
        context: %{resultAsArray: true}
      }

      assert Native.rows([[1_466_985_600_000, "#en", "a", 2, 4]], query) == [
               %{
                 "__time" => 1_466_985_600_000,
                 "channel" => "#en",
                 "p" => "a",
                 "rows" => 2,
                 "doubled" => 4
               }
             ]
    end

    test "concatenates scan batches in either result format" do
      query = %{queryType: "scan", columns: ["__time", "page"]}

      results = [
        %{"columns" => ["__time", "page"], "events" => [%{"__time" => 1, "page" => "a"}]},
        %{"columns" => ["__time", "page"], "events" => [[2, "b"], [3, "c"]]}
      ]

      assert Native.rows(results, query) == [
               %{"__time" => 1, "page" => "a"},
               %{"__time" => 2, "page" => "b"},
               %{"__time" => 3, "page" => "c"}
             ]
    end

    test "names scan arrays with the query's columns when a batch doesn't list them" do
      query = %{queryType: "scan", columns: ["__time", "page"]}

      assert Native.rows([%{"events" => [[1, "a"]]}], query) == [%{"__time" => 1, "page" => "a"}]
    end

    test "names windowOperator results with :columns" do
      query = %{queryType: "windowOperator"}

      assert Native.rows([["a", 1]], query, columns: ["page", "rank"]) == [
               %{"page" => "a", "rank" => 1}
             ]

      assert_raise ArgumentError, ~r/Pass them as the :columns option/, fn ->
        Native.rows([["a", 1]], query)
      end
    end

    test "raises when an array row doesn't match its columns" do
      query = %{queryType: "groupBy", dimensions: ["page"], context: %{resultAsArray: true}}

      assert_raise ArgumentError, ~r/expected 1 values/, fn ->
        Native.rows([["a", 1]], query)
      end
    end

    test "raises for query types it doesn't flatten" do
      assert_raise ArgumentError, ~r/got: "timeBoundary"/, fn ->
        Native.rows([], %{queryType: "timeBoundary"})
      end
    end
  end
end
