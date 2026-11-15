defmodule Druid.Client.SQL.StatementTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.SQL.Statement

  @path "/druid/v2/sql/statements"

  test "submit/3 runs the statement asynchronously" do
    {conn, body} =
      request!(
        Statement.submit("SELECT 1", [], context: %{sqlQueryId: "q1", executionMode: "SYNC"})
      )

    assert {conn.method, conn.request_path} == {"POST", @path}

    assert body == %{
             "query" => "SELECT 1",
             "parameters" => [],
             "context" => %{
               "sqlQueryId" => "q1",
               "executionMode" => "ASYNC",
               "enableWindowing" => true,
               "skipEmptyBuckets" => false,
               "sqlStringifyArrays" => false
             }
           }
  end

  test "status/2" do
    assert_request(Statement.status("q1"), "GET", @path <> "/q1")
    assert_request(Statement.status("q1", detail: true), "GET", @path <> "/q1", "detail=true")
  end

  test "results/2" do
    assert_request(Statement.results("q1"), "GET", @path <> "/q1/results")

    assert_request(
      Statement.results("q1", page: 0, result_format: "array", filename: "out.json"),
      "GET",
      @path <> "/q1/results",
      "page=0&resultFormat=array&filename=out.json"
    )
  end

  test "cancel/1" do
    assert_request(Statement.cancel("q1"), "DELETE", @path <> "/q1")
  end
end
