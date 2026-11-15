defmodule Druid.Client.SupervisorTest do
  use ExUnit.Case, async: true
  alias Druid.Client
  alias Druid.Client.Supervisor

  defp request!(req) do
    Client.request!(req, plug: TestPlug, host: "localhost", port: 8888)
    assert_received {:request, conn, body}
    {conn, body}
  end

  test "list/0" do
    {conn, _} = request!(Supervisor.list())
    assert conn.method == "GET"
    assert conn.request_path == "/druid/indexer/v1/supervisor"
  end

  test "get/1" do
    {conn, _} = request!(Supervisor.get("wikipedia"))
    assert conn.method == "GET"
    assert conn.request_path == "/druid/indexer/v1/supervisor/wikipedia"
  end

  test "status/1" do
    {conn, _} = request!(Supervisor.status("wikipedia"))
    assert conn.method == "GET"
    assert conn.request_path == "/druid/indexer/v1/supervisor/wikipedia/status"
  end

  describe "submit/2" do
    test "posts the spec and skips restarting unmodified supervisors by default" do
      spec = %{"type" => "kafka", "spec" => %{"dataSchema" => %{"dataSource" => "wikipedia"}}}
      {conn, body} = request!(Supervisor.submit(spec))

      assert conn.method == "POST"
      assert conn.request_path == "/druid/indexer/v1/supervisor"
      assert conn.query_string == "skipRestartIfUnmodified=true"
      assert body == spec
    end

    test "can force a restart" do
      {conn, _} = request!(Supervisor.submit(%{}, skip_restart_if_unmodified: false))
      assert conn.query_string == "skipRestartIfUnmodified=false"
    end
  end

  for action <- [:suspend, :resume, :reset, :terminate] do
    test "#{action}/1" do
      {conn, _} = request!(apply(Supervisor, unquote(action), ["my/supervisor"]))
      assert conn.method == "POST"

      assert conn.request_path ==
               "/druid/indexer/v1/supervisor/my%2Fsupervisor/#{unquote(action)}"
    end
  end
end
