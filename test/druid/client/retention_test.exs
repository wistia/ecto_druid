defmodule Druid.Client.RetentionTest do
  use ExUnit.Case, async: true
  alias Druid.Client
  alias Druid.Client.Retention

  defp request!(req) do
    Client.request!(req, plug: TestPlug, host: "localhost", port: 8888)
    assert_received {:request, conn, body}
    {conn, body}
  end

  test "all/0" do
    {conn, _} = request!(Retention.all())
    assert {conn.method, conn.request_path} == {"GET", "/druid/coordinator/v1/rules"}
  end

  test "get/1 escapes the data source" do
    {conn, _} = request!(Retention.get("a/b"))
    assert {conn.method, conn.request_path} == {"GET", "/druid/coordinator/v1/rules/a%2Fb"}
  end

  test "set/3 posts the rules with audit headers" do
    rules = [%{"type" => "dropForever"}]
    {conn, body} = request!(Retention.set("wikipedia", rules, author: "me", comment: "why"))

    assert {conn.method, conn.request_path} == {"POST", "/druid/coordinator/v1/rules/wikipedia"}
    assert body == rules
    assert Plug.Conn.get_req_header(conn, "x-druid-author") == ["me"]
    assert Plug.Conn.get_req_header(conn, "x-druid-comment") == ["why"]
  end

  test "set/3 without audit options sends no audit headers" do
    {conn, _} = request!(Retention.set("wikipedia", []))
    assert Plug.Conn.get_req_header(conn, "x-druid-author") == []
  end

  test "history/2" do
    {conn, _} = request!(Retention.history("wikipedia", count: 5))
    assert conn.request_path == "/druid/coordinator/v1/rules/wikipedia/history"
    assert conn.query_string == "count=5"
  end

  test "tiers/0" do
    {conn, _} = request!(Retention.tiers())
    assert conn.request_path == "/druid/coordinator/v1/tiers"
  end
end
