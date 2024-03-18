defmodule Druid.Client.TaskTest do
  use ExUnit.Case, async: true
  alias Druid.Client
  alias Druid.Client.Task

  describe "all/0" do
    test "produces the expected request" do
      Task.all()
      |> Client.request!(plug: TestPlug, host: "localhost", port: 8082)

      assert_received {:request, conn, _body}

      assert conn.method == "GET"
      assert conn.request_path == "/druid/indexer/v1/tasks"
    end
  end

  describe "status/1" do
    test "produces the expected request" do
      Task.status("123")
      |> Client.request!(plug: TestPlug, host: "localhost", port: 8082)

      assert_received {:request, conn, _body}

      assert conn.method == "GET"
      assert conn.request_path == "/druid/indexer/v1/task/123/status"
    end
  end

  describe "result/1" do
    test "produces the expected request" do
      Task.result("123")
      |> Client.request!(plug: TestPlug, host: "localhost", port: 8082)

      assert_received {:request, conn, _body}

      assert conn.method == "GET"
      assert conn.request_path == "/druid/indexer/v1/task/123"
    end
  end
end
