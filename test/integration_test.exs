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
end
