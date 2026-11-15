defmodule Druid.Client.SupervisorTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.Supervisor

  @path "/druid/indexer/v1/supervisor"

  test "list/0" do
    {conn, _} = request!(Supervisor.list())
    assert conn.method == "GET"
    assert conn.request_path == "/druid/indexer/v1/supervisor"
  end

  test "list/1 asks for full specs or states" do
    assert_request(Supervisor.list(full: true), "GET", @path, "full=true")
    assert_request(Supervisor.list(state: true), "GET", @path, "state=true")
    assert_request(Supervisor.list(full: false), "GET", @path)
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

  test "health/1" do
    assert_request(Supervisor.health("wikipedia"), "GET", @path <> "/wikipedia/health")
  end

  test "stats/1" do
    assert_request(Supervisor.stats("wikipedia"), "GET", @path <> "/wikipedia/stats")
  end

  test "history/0" do
    assert_request(Supervisor.history(), "GET", @path <> "/history")
  end

  test "history/2" do
    assert_request(Supervisor.history("wikipedia"), "GET", @path <> "/wikipedia/history")

    assert_request(
      Supervisor.history("wikipedia", count: 2),
      "GET",
      @path <> "/wikipedia/history",
      "count=2"
    )
  end

  test "reset_offsets/2" do
    offsets = %{
      "type" => "kafka",
      "partitions" => %{
        "type" => "end",
        "stream" => "wikipedia",
        "partitionOffsetMap" => %{"0" => 100}
      }
    }

    assert_request(
      Supervisor.reset_offsets("wikipedia", offsets),
      "POST",
      @path <> "/wikipedia/resetOffsets",
      "",
      offsets
    )
  end

  test "handoff/2" do
    assert_request(
      Supervisor.handoff("wikipedia", [0, 1]),
      "POST",
      @path <> "/wikipedia/taskGroups/handoff",
      "",
      %{"taskGroupIds" => [0, 1]}
    )
  end

  for {fun, action} <- [
        suspend_all: "suspendAll",
        resume_all: "resumeAll",
        terminate_all: "terminateAll"
      ] do
    test "#{fun}/0" do
      assert_request(Supervisor.unquote(fun)(), "POST", @path <> "/" <> unquote(action))
    end
  end
end
