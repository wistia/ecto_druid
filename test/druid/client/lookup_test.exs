defmodule Druid.Client.LookupTest do
  use ExUnit.Case, async: true
  alias Druid.Client
  alias Druid.Client.Lookup

  @base "/druid/coordinator/v1/lookups"

  defp request!(req) do
    Client.request!(req, plug: TestPlug, host: "localhost", port: 8888)
    assert_received {:request, conn, body}
    {conn, body}
  end

  test "all/0" do
    {conn, _} = request!(Lookup.all())
    assert {conn.method, conn.request_path} == {"GET", @base <> "/config/all"}
  end

  test "get/2" do
    {conn, _} = request!(Lookup.get("__default", "countries"))
    assert {conn.method, conn.request_path} == {"GET", @base <> "/config/__default/countries"}
  end

  test "set/4 wraps the factory with the version" do
    factory = %{"type" => "map", "map" => %{"a" => "b"}}
    {conn, body} = request!(Lookup.set("__default", "a/b", "v1", factory))

    assert {conn.method, conn.request_path} == {"POST", @base <> "/config/__default/a%2Fb"}
    assert body == %{"version" => "v1", "lookupExtractorFactory" => factory}
  end

  test "initialize/0 posts an empty map" do
    {conn, body} = request!(Lookup.initialize())
    assert {conn.method, conn.request_path, body} == {"POST", @base <> "/config", %{}}
  end

  test "delete/2" do
    {conn, _} = request!(Lookup.delete("__default", "countries"))
    assert {conn.method, conn.request_path} == {"DELETE", @base <> "/config/__default/countries"}
  end

  test "status/2" do
    {conn, _} = request!(Lookup.status("__default", "countries"))
    assert {conn.method, conn.request_path} == {"GET", @base <> "/status/__default/countries"}
  end
end
