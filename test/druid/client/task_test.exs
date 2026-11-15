defmodule Druid.Client.TaskTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.Task

  @v1 "/druid/indexer/v1"

  describe "all/1" do
    test "lists every task" do
      assert_request(Task.all(), "GET", @v1 <> "/tasks")
    end

    test "filters tasks" do
      req =
        Task.all(
          state: "complete",
          datasource: "wikipedia",
          created_time_interval: "2024-01-01/2024-01-02",
          max: 10,
          type: "index_parallel"
        )

      assert_request(
        req,
        "GET",
        @v1 <> "/tasks",
        "state=complete&datasource=wikipedia&createdTimeInterval=2024-01-01_2024-01-02&max=10&type=index_parallel"
      )
    end
  end

  for {fun, endpoint} <- [
        complete: "completeTasks",
        running: "runningTasks",
        waiting: "waitingTasks",
        pending: "pendingTasks"
      ] do
    test "#{fun}/1" do
      assert_request(Task.unquote(fun)(), "GET", @v1 <> "/" <> unquote(endpoint))

      assert_request(
        Task.unquote(fun)(datasource: "wikipedia"),
        "GET",
        @v1 <> "/" <> unquote(endpoint),
        "datasource=wikipedia"
      )
    end
  end

  test "status/1" do
    assert_request(Task.status("123"), "GET", @v1 <> "/task/123/status")
  end

  test "statuses/1" do
    assert_request(Task.statuses(["a", "b"]), "POST", @v1 <> "/taskStatus", "", ["a", "b"])
  end

  test "result/1" do
    assert_request(Task.result("123"), "GET", @v1 <> "/task/123")
  end

  test "reports/1" do
    assert_request(Task.reports("123"), "GET", @v1 <> "/task/123/reports")
  end

  test "log/2" do
    assert_request(Task.log("123"), "GET", @v1 <> "/task/123/log")
    assert_request(Task.log("123", offset: -1000), "GET", @v1 <> "/task/123/log", "offset=-1000")
  end

  test "submit/1" do
    task = %{"type" => "index_parallel", "spec" => %{}}
    assert_request(Task.submit(task), "POST", @v1 <> "/task", "", task)
  end

  test "shutdown/1 escapes the task ID" do
    assert_request(Task.shutdown("query/1"), "POST", @v1 <> "/task/query%2F1/shutdown")
  end

  test "shutdown_all/1" do
    assert_request(
      Task.shutdown_all("wikipedia"),
      "POST",
      @v1 <> "/datasources/wikipedia/shutdownAllTasks"
    )
  end

  test "delete_pending_segments/1" do
    assert_request(
      Task.delete_pending_segments("wikipedia"),
      "DELETE",
      @v1 <> "/pendingSegments/wikipedia"
    )
  end
end
