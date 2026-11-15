defmodule Druid.Client.CompactionTest do
  use ExUnit.Case, async: true
  alias Druid.Client
  alias Druid.Client.Compaction

  @base "/druid/indexer/v1/compaction"

  defp request!(req) do
    Client.request!(req, plug: TestPlug, host: "localhost", port: 8888)
    assert_received {:request, conn, body}
    {conn, body}
  end

  test "all/0" do
    {conn, _} = request!(Compaction.all())
    assert {conn.method, conn.request_path} == {"GET", @base <> "/config/datasources"}
  end

  test "get/1 escapes the data source" do
    {conn, _} = request!(Compaction.get("a/b"))
    assert {conn.method, conn.request_path} == {"GET", @base <> "/config/datasources/a%2Fb"}
  end

  test "set/2 posts the config under its data source with audit headers" do
    config = %{"dataSource" => "wikipedia", "skipOffsetFromLatest" => "P1D"}
    {conn, body} = request!(Compaction.set(config, author: "me", comment: "why"))

    assert {conn.method, conn.request_path} == {"POST", @base <> "/config/datasources/wikipedia"}
    assert body == config
    assert Plug.Conn.get_req_header(conn, "x-druid-author") == ["me"]
    assert Plug.Conn.get_req_header(conn, "x-druid-comment") == ["why"]
  end

  test "delete/2" do
    {conn, _} = request!(Compaction.delete("wikipedia", comment: "gone"))

    assert {conn.method, conn.request_path} ==
             {"DELETE", @base <> "/config/datasources/wikipedia"}

    assert Plug.Conn.get_req_header(conn, "x-druid-comment") == ["gone"]
  end

  test "history/2" do
    {conn, _} = request!(Compaction.history("wikipedia", count: 2))
    assert conn.request_path == @base <> "/config/datasources/wikipedia/history"
    assert conn.query_string == "count=2"
  end

  test "statuses/0" do
    {conn, _} = request!(Compaction.statuses())
    assert {conn.method, conn.request_path} == {"GET", @base <> "/status/datasources"}
  end

  test "status/1" do
    {conn, _} = request!(Compaction.status("wikipedia"))
    assert conn.request_path == @base <> "/status/datasources/wikipedia"
  end

  test "cluster/0 and set_cluster/1" do
    {conn, _} = request!(Compaction.cluster())
    assert {conn.method, conn.request_path} == {"GET", @base <> "/config/cluster"}

    {conn, body} = request!(Compaction.set_cluster(%{"useSupervisors" => true}))
    assert {conn.method, conn.request_path} == {"POST", @base <> "/config/cluster"}
    assert body == %{"useSupervisors" => true}
  end
end
