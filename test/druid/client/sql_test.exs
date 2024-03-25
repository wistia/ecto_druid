defmodule Druid.Client.SQLTest do
  use ExUnit.Case
  alias Druid.Client
  alias Druid.Client.SQL
  alias Plug.Conn

  describe "query/3" do
    test "produces the expected request" do
      query = "SELECT * FROM wikipedia"
      params = []
      opts = [context: %{sqlQueryId: "123"}]

      SQL.query(query, params, opts)
      |> Client.request!(plug: TestPlug, host: "localhost", port: 8082)

      assert_received {:request, conn, body}

      assert conn.method == "POST"
      assert conn.request_path == "/druid/v2/sql"
      assert Conn.get_req_header(conn, "content-type") == ["application/json"]

      assert body == %{
               "context" => %{
                 "enableWindowing" => true,
                 "skipEmptyBuckets" => false,
                 "sqlQueryId" => "123",
                 "sqlStringifyArrays" => false
               },
               "header" => false,
               "parameters" => [],
               "query" => "SELECT * FROM wikipedia",
               "resultFormat" => "array",
               "typesHeader" => false
             }
    end
  end

  describe "insert/3" do
    test "produces the expected request" do
      query = "INSERT INTO wikipedia SELECT * FROM wikipedia"
      params = []
      opts = [context: %{sqlQueryId: "123"}]

      SQL.insert(query, params, opts)
      |> Client.request!(plug: TestPlug, host: "localhost", port: 8082)

      assert_received {:request, conn, body}

      assert conn.method == "POST"
      assert conn.request_path == "/druid/v2/sql/task"
      assert Conn.get_req_header(conn, "content-type") == ["application/json"]

      assert body == %{
               "context" => %{
                 "enableWindowing" => true,
                 "skipEmptyBuckets" => false,
                 "sqlQueryId" => "123",
                 "sqlStringifyArrays" => false
               },
               "parameters" => [],
               "query" => "INSERT INTO wikipedia SELECT * FROM wikipedia"
             }
    end
  end
end
