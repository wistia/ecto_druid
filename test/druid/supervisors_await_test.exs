defmodule Druid.SupervisorsAwaitTest do
  use ExUnit.Case, async: true
  alias Druid.Supervisors
  alias Ecto.Adapters.Druid.TestRepo

  @status_path "/druid/indexer/v1/supervisor/events/status"

  # Answers supervisor status requests with each of `statuses` in turn,
  # repeating the last, and task status requests with each task's states in
  # turn. Requests are sent to the test process.
  defp druid(statuses, opts \\ []) do
    test_pid = self()
    {:ok, agent} = Agent.start_link(fn -> %{statuses: statuses, tasks: opts[:tasks] || %{}} end)
    task_count = Keyword.get(opts, :task_count, 1)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:druid, conn.method, conn.request_path, body})

      case {conn.method, conn.path_info} do
        {"GET", [_, _, _, "supervisor", "events", "status"]} ->
          payload = next(agent, :statuses)
          Req.Test.json(conn, %{"id" => "events", "payload" => payload})

        {"GET", [_, _, _, "supervisor", "events"]} ->
          Req.Test.json(conn, %{
            "type" => "kafka",
            "spec" => %{"ioConfig" => %{"taskCount" => task_count}}
          })

        {"POST", [_, _, _, "supervisor", "events", "taskGroups", "handoff"]} ->
          conn |> Plug.Conn.put_status(202) |> Plug.Conn.send_resp(202, "")

        {"GET", [_, _, _, "task", task_id, "status"]} ->
          state = next(agent, {:task, task_id})

          Req.Test.json(conn, %{
            "task" => task_id,
            "status" => %{"id" => task_id, "status" => state, "dataSource" => "events"}
          })

        {"GET", [_, _, _, "datasources", "events", "loadstatus"]} ->
          Req.Test.json(conn, %{"events" => 0})

        # The Broker lists the data source
        {"POST", ["druid", "v2", "sql"]} ->
          Req.Test.json(conn, [[1]])
      end
    end
  end

  defp next(agent, :statuses) do
    Agent.get_and_update(agent, fn
      %{statuses: [last]} = state -> {last, state}
      %{statuses: [status | rest]} = state -> {status, %{state | statuses: rest}}
    end)
  end

  defp next(agent, {:task, id}) do
    Agent.get_and_update(agent, fn state ->
      case Map.fetch!(state.tasks, id) do
        [last] -> {last, state}
        [current | rest] -> {current, put_in(state.tasks[id], rest)}
      end
    end)
  end

  defp running(tasks),
    do: %{"state" => "RUNNING", "detailedState" => "RUNNING", "activeTasks" => tasks}

  defp task(id, current_offsets),
    do: %{"id" => id, "startingOffsets" => %{"0" => 5}, "currentOffsets" => current_offsets}

  describe "await_running/3" do
    test "waits until every active task has read from the stream" do
      reading = running([task("t1", %{"0" => 5}), task("t2", %{"1" => 0})])

      plug =
        druid([
          %{"state" => "PENDING", "detailedState" => "PENDING", "activeTasks" => []},
          running([]),
          # The task is created, but hasn't started
          running([task("t1", %{}), task("t2", %{})]),
          running([task("t1", %{"0" => 5}), task("t2", %{})]),
          reading
        ])

      assert {:ok, ^reading} =
               Supervisors.await_running(TestRepo, "events", plug: plug, poll_interval: 1)

      for _ <- 1..5, do: assert_received({:druid, "GET", @status_path, _})
      refute_received {:druid, _, _, _}
    end

    test "uses the supervisors config's host and port" do
      plug = fn conn ->
        send(self(), {:host, conn.host, conn.port})
        Req.Test.json(conn, %{"payload" => running([task("t1", %{"0" => 1})])})
      end

      assert {:ok, _} = Supervisors.await_running(TestRepo, "events", plug: plug)
      # :port comes from the test config's :supervisors
      assert_received {:host, "localhost", 9888}
    end

    test "returns an error when the supervisor is suspended" do
      plug = druid([%{"state" => "SUSPENDED", "suspended" => true, "activeTasks" => []}])

      assert {:error, %Supervisors.Error{reason: :suspended, supervisor_id: "events"} = error} =
               Supervisors.await_running(TestRepo, "events", plug: plug)

      assert Exception.message(error) == "supervisor events is suspended"
    end

    test "returns an error with recent errors when the supervisor is unhealthy" do
      status = %{
        "state" => "UNHEALTHY_SUPERVISOR",
        "detailedState" => "UNABLE_TO_CONNECT_TO_STREAM",
        "activeTasks" => [],
        "recentErrors" => [
          %{"exceptionClass" => "org.apache.kafka.common.errors.TimeoutException"},
          %{"exceptionClass" => "org.apache.kafka.common.errors.TimeoutException"}
        ]
      }

      assert {:error, %Supervisors.Error{reason: :unhealthy, status: ^status} = error} =
               Supervisors.await_running(TestRepo, "events", plug: druid([status]))

      assert Exception.message(error) ==
               "supervisor events is UNABLE_TO_CONNECT_TO_STREAM: " <>
                 "org.apache.kafka.common.errors.TimeoutException"
    end

    test "times out with the last state" do
      plug = druid([%{"state" => "PENDING", "detailedState" => "CONNECTING_TO_STREAM"}])

      assert {:error, %Supervisors.Error{reason: :timeout, status: %{}} = error} =
               Supervisors.await_running(TestRepo, "events",
                 plug: plug,
                 poll_interval: 5,
                 timeout: 20
               )

      assert Exception.message(error) ==
               "timed out waiting for supervisor events to start reading (it is CONNECTING_TO_STREAM)"
    end

    test "returns request errors" do
      plug = fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "nope"})
      end

      assert {:error, %Druid.Client.RequestError{status: 404}} =
               Supervisors.await_running(TestRepo, "events", plug: plug)
    end
  end

  describe "handoff/3" do
    test "hands off every task group and waits for the active tasks to finish" do
      plug =
        druid([running([task("t1", %{"0" => 9}), task("t2", %{"1" => 3})])],
          task_count: 2,
          tasks: %{"t1" => ["RUNNING", "SUCCESS"], "t2" => ["RUNNING", "RUNNING", "SUCCESS"]}
        )

      assert {:ok,
              [%{"id" => "t1", "status" => "SUCCESS"}, %{"id" => "t2", "status" => "SUCCESS"}]} =
               Supervisors.handoff(TestRepo, "events", plug: plug, poll_interval: 1)

      assert_received {:druid, "GET", @status_path, _}
      assert_received {:druid, "GET", "/druid/indexer/v1/supervisor/events", _}

      assert_received {:druid, "POST", "/druid/indexer/v1/supervisor/events/taskGroups/handoff",
                       body}

      assert Jason.decode!(body) == %{"taskGroupIds" => [0, 1]}

      for _ <- 1..2, do: assert_received({:druid, "GET", "/druid/indexer/v1/task/t1/status", _})
      for _ <- 1..3, do: assert_received({:druid, "GET", "/druid/indexer/v1/task/t2/status", _})
      refute_received {:druid, _, _, _}
    end

    test "hands off only the given task groups" do
      plug = druid([running([task("t1", %{"0" => 9})])], tasks: %{"t1" => ["SUCCESS"]})

      assert {:ok, [_]} = Supervisors.handoff(TestRepo, "events", plug: plug, task_groups: [3])

      refute_received {:druid, "GET", "/druid/indexer/v1/supervisor/events", _}

      assert_received {:druid, "POST", "/druid/indexer/v1/supervisor/events/taskGroups/handoff",
                       body}

      assert Jason.decode!(body) == %{"taskGroupIds" => [3]}
    end

    test "waits for segments to load" do
      plug = druid([running([task("t1", %{"0" => 9})])], tasks: %{"t1" => ["SUCCESS"]})

      assert {:ok, [_]} =
               Supervisors.handoff(TestRepo, "events", plug: plug, wait_for_segments: true)

      assert_received {:druid, "GET", "/druid/coordinator/v1/datasources/events/loadstatus", _}
      assert_received {:druid, "POST", "/druid/v2/sql", _}
    end

    test "returns the task IDs without waiting" do
      plug = druid([running([task("t1", %{"0" => 9}), task("t2", %{})])])

      assert {:ok, ["t1", "t2"]} =
               Supervisors.handoff(TestRepo, "events", plug: plug, wait: false)

      refute_received {:druid, "GET", "/druid/indexer/v1/task/" <> _, _}
    end

    test "returns the error of a task that fails" do
      plug = druid([running([task("t1", %{"0" => 9})])], tasks: %{"t1" => ["FAILED"]})

      assert {:error, %Druid.Tasks.Error{reason: :failed, task_id: "t1"}} =
               Supervisors.handoff(TestRepo, "events", plug: plug)
    end

    test "shares the timeout between tasks" do
      plug =
        druid([running([task("t1", %{"0" => 9}), task("t2", %{"1" => 3})])],
          tasks: %{"t1" => ["RUNNING"], "t2" => ["SUCCESS"]}
        )

      assert {:error, %Druid.Tasks.Error{reason: :timeout, task_id: "t1"}} =
               Supervisors.handoff(TestRepo, "events", plug: plug, poll_interval: 5, timeout: 20)
    end

    test "returns an error when there are no active tasks" do
      plug = druid([running([])])

      assert {:error, %Supervisors.Error{reason: :no_active_tasks} = error} =
               Supervisors.handoff(TestRepo, "events", plug: plug)

      assert Exception.message(error) == "supervisor events has no active tasks to hand off"
      refute_received {:druid, "POST", _, _}
    end
  end
end
