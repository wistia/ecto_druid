defmodule Ecto.Adapters.Druid.NativeQueryTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  # Answers every request with `response` and sends each request body to the
  # test process.
  defp druid(response) do
    test = self()

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {conn.request_path, Jason.decode!(body)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end
  end

  @topn %{
    queryType: "topN",
    dataSource: "wikipedia",
    dimension: "page",
    aggregations: [%{type: "count", name: "rows"}]
  }

  @topn_results [
    %{"timestamp" => "2016-06-27T00:00:00.000Z", "result" => [%{"page" => "a", "rows" => 2}]}
  ]

  describe "native_query/2" do
    test "flattens results into rows by default" do
      assert TestRepo.native_query(@topn, plug: druid(@topn_results)) == [
               %{"__time" => "2016-06-27T00:00:00.000Z", "page" => "a", "rows" => 2}
             ]

      assert_received {"/druid/v2/", body}
      assert body["queryType"] == "topN"
    end

    test "returns Druid's response as is with raw: true" do
      assert TestRepo.native_query(@topn, plug: druid(@topn_results), raw: true) ==
               @topn_results
    end

    test "names array results with :columns" do
      query = %{queryType: "windowOperator", dataSource: "wikipedia"}

      assert TestRepo.native_query(query, plug: druid([["a", 1]]), columns: ["page", "rank"]) ==
               [%{"page" => "a", "rank" => 1}]
    end

    test "returns results of query types it doesn't flatten as is" do
      results = [%{"timestamp" => "2016-06-27T00:00:00.000Z", "result" => %{"minTime" => "x"}}]
      query = %{queryType: "timeBoundary", dataSource: "wikipedia"}

      assert TestRepo.native_query(query, plug: druid(results)) == results
    end
  end
end
