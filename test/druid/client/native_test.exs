defmodule Druid.Client.NativeTest do
  use ExUnit.Case
  alias Druid.Client
  alias Druid.Client.Native
  alias Plug.Conn

  describe "query/3" do
    test "produces the expected request" do
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

      Native.query(query)
      |> Client.request!(plug: TestPlug, host: "localhost", port: 8082)

      assert_received {:request, conn, body}

      assert conn.method == "POST"
      assert conn.request_path == "/druid/v2/"
      assert Conn.get_req_header(conn, "content-type") == ["application/json"]

      assert body == %{
               "aggregations" => [
                 %{"fieldName" => "added", "name" => "added", "type" => "longSum"},
                 %{"fieldName" => "deleted", "name" => "deleted", "type" => "longSum"}
               ],
               "dataSource" => "wikipedia",
               "granularity" => "all",
               "intervals" => ["2013-01-01/2048-01-02"],
               "limit" => 3,
               "queryType" => "timeseries"
             }
    end
  end
end
