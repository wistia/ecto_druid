defmodule Druid.TasksTest do
  use ExUnit.Case, async: true
  alias Druid.Tasks
  alias Druid.Tasks.Spec
  alias Ecto.Adapters.Druid.TestRepo

  @moduletag :tmp_dir

  defmodule AuthRepo do
    def config, do: [host: "localhost", port: 8888, auth: {:bearer, "repo"}]
  end

  defmodule TasksAuthRepo do
    def config, do: AuthRepo.config() ++ [tasks: [auth: {:bearer, "tasks"}]]
  end

  @index """
  {
    "type": "index_parallel",
    "spec": {
      "ioConfig": {"type": "index_parallel", "inputSource": {"type": "s3", "prefixes": [<%= json @prefix %>]}},
      "tuningConfig": {"type": "index_parallel", "maxNumConcurrentSubTasks": <%= @subtasks %>},
      "dataSchema": {"dataSource": "events", "granularitySpec": {"intervals": [<%= json @interval %>]}}
    }
  }
  """

  defp write!(dir, name, contents) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  # Stands in for configured assigns, with `extra` assigns merged in
  defp opts(dir, extra \\ []) do
    {assigns, extra} = Keyword.pop(extra, :assigns, %{})
    assigns = Map.merge(%{prefix: "s3://bucket/events/", subtasks: 1}, assigns)
    Keyword.merge([path: dir, assigns: assigns, poll_interval: 1], extra)
  end

  # A fake Overlord and Coordinator. `statuses` are the task states to report
  # on successive status requests, and `load` the segments left to load on
  # successive load status requests. The last of each repeats.
  defp druid(statuses, opts \\ []) do
    {:ok, agent} = Agent.start_link(fn -> {statuses, Keyword.get(opts, :load, [0])} end)
    test_pid = self()
    status_extra = Keyword.get(opts, :status, %{})

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:druid, conn.method, conn.request_path, conn.query_string, body})

      case {conn.method, conn.path_info} do
        {"POST", ["druid", "indexer", "v1", "task"]} ->
          if Keyword.get(opts, :reject) do
            conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad task"})
          else
            Req.Test.json(conn, %{"task" => "task-1"})
          end

        {"GET", ["druid", "indexer", "v1", "task", id, "status"]} ->
          state = Agent.get_and_update(agent, fn {s, l} -> {hd(s), {tl_or_last(s), l}} end)

          status =
            Map.merge(
              %{"id" => id, "status" => state, "dataSource" => "events", "duration" => 1500},
              status_extra
            )

          Req.Test.json(conn, %{"task" => id, "status" => status})

        {"GET", ["druid", "coordinator", "v1", "datasources", ds, "loadstatus"]} ->
          left = Agent.get_and_update(agent, fn {s, l} -> {hd(l), {s, tl_or_last(l)}} end)
          Req.Test.json(conn, %{ds => left})
      end
    end
  end

  defp tl_or_last([last]), do: [last]
  defp tl_or_last([_ | rest]), do: rest

  describe "render/2" do
    test "renders templates", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", @index)

      assert [%Spec{name: "events", data_source: "events", spec: spec}] =
               Tasks.render(TestRepo, opts(dir, assigns: %{interval: "2026-11-01/P1D"}))

      assert get_in(spec, ["spec", "ioConfig", "inputSource", "prefixes"]) ==
               ["s3://bucket/events/"]

      assert get_in(spec, ["spec", "dataSchema", "granularitySpec", "intervals"]) ==
               ["2026-11-01/P1D"]
    end

    test "merges call assigns over the configured :tasks assigns", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", ~s({"type": "kill", "dataSource": "events",
        "maxParse": <%= @max_parse_exceptions %>, "interval": <%= json @interval %>}))

      # TestRepo configures max_parse_exceptions under :tasks
      [%Spec{spec: spec}] = Tasks.render(TestRepo, path: dir, assigns: %{interval: "x"})
      assert spec["maxParse"] == 0
      assert spec["interval"] == "x"
    end

    test "per-template assigns apply", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", @index)

      [%Spec{spec: spec}] =
        Tasks.render(
          TestRepo,
          opts(dir, assigns: %{interval: "i"}, specs: %{"events" => %{subtasks: 4}})
        )

      assert spec["spec"]["tuningConfig"]["maxNumConcurrentSubTasks"] == 4
    end

    test "raises on a missing assign", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", @index)

      assert_raise Tasks.Error, ~r/assign @interval is not set/, fn ->
        Tasks.render(TestRepo, opts(dir))
      end
    end

    test "raises on unknown names in :only", %{tmp_dir: dir} do
      write!(dir, "events.json", ~s({"type": "kill", "dataSource": "events"}))

      assert_raise Tasks.Error, ~r/no task templates named: other/, fn ->
        Tasks.render(TestRepo, opts(dir, only: ["other"]))
      end
    end

    test "raises when a template isn't a JSON object", %{tmp_dir: dir} do
      write!(dir, "events.json", "[]")

      assert_raise Tasks.Error, ~r/must render a JSON object/, fn ->
        Tasks.render(TestRepo, opts(dir))
      end
    end
  end

  describe "data_source/1" do
    test "reads ingestion and non-ingestion specs" do
      assert Tasks.data_source(%{"spec" => %{"dataSchema" => %{"dataSource" => "a"}}}) == "a"
      assert Tasks.data_source(%{"type" => "kill", "dataSource" => "b"}) == "b"
      assert Tasks.data_source(%{"type" => "noop"}) == nil
    end
  end

  describe "submit/3" do
    test "submits a template by name and returns the task ID", %{tmp_dir: dir} do
      write!(dir, "events.json", ~s({"type": "kill", "dataSource": "events"}))

      assert {:ok, "task-1"} = Tasks.submit(TestRepo, "events", opts(dir, plug: druid([])))

      assert_received {:druid, "POST", "/druid/indexer/v1/task", "", body}
      assert Jason.decode!(body) == %{"type" => "kill", "dataSource" => "events"}
    end

    test "submits a map or a rendered spec", %{tmp_dir: dir} do
      plug = druid([])
      assert {:ok, "task-1"} = Tasks.submit(TestRepo, %{"type" => "noop"}, plug: plug)

      write!(dir, "events.json", ~s({"type": "kill", "dataSource": "events"}))
      [spec] = Tasks.render(TestRepo, opts(dir))
      assert {:ok, "task-1"} = Tasks.submit(TestRepo, spec, plug: plug)
    end

    test "returns request errors" do
      assert {:error, %Druid.Client.RequestError{status: 400}} =
               Tasks.submit(TestRepo, %{"type" => "noop"}, plug: druid([], reject: true))
    end

    test "uses the tasks host and port, falling back to the repo's" do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:host, conn.host, conn.port})
        druid([]).(conn)
      end

      Tasks.submit(TestRepo, %{"type" => "noop"}, plug: plug)
      # TestRepo configures port 9888 under :tasks
      assert_received {:host, "localhost", 9888}

      Tasks.submit(TestRepo, %{"type" => "noop"}, plug: plug, port: 8888)
      assert_received {:host, "localhost", 8888}
    end

    test "sends the repo's auth, overridden by the tasks config and then the call" do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:auth, Plug.Conn.get_req_header(conn, "authorization")})
        druid([]).(conn)
      end

      Tasks.submit(__MODULE__.AuthRepo, %{"type" => "noop"}, plug: plug)
      assert_received {:auth, ["Bearer repo"]}

      Tasks.submit(__MODULE__.TasksAuthRepo, %{"type" => "noop"}, plug: plug)
      assert_received {:auth, ["Bearer tasks"]}

      Tasks.submit(__MODULE__.TasksAuthRepo, %{"type" => "noop"},
        plug: plug,
        auth: {:bearer, "call"}
      )

      assert_received {:auth, ["Bearer call"]}
    end
  end

  describe "await/3" do
    test "polls until the task succeeds" do
      assert {:ok, %{"id" => "t", "status" => "SUCCESS"}} =
               Tasks.await(TestRepo, "t",
                 plug: druid(["RUNNING", "RUNNING", "SUCCESS"]),
                 poll_interval: 1
               )

      for _ <- 1..3, do: assert_received({:druid, "GET", "/druid/indexer/v1/task/t/status", _, _})
      refute_received {:druid, _, _, _, _}
    end

    test "returns an error when the task fails" do
      plug = druid(["RUNNING", "FAILED"], status: %{"errorMsg" => "out of disk"})

      assert {:error, %Tasks.Error{reason: :failed, task_id: "t", status: %{}} = error} =
               Tasks.await(TestRepo, "t", plug: plug, poll_interval: 1)

      assert Exception.message(error) == "task t failed: out of disk"
    end

    test "times out" do
      assert {:error, %Tasks.Error{reason: :timeout, task_id: "t", message: message}} =
               Tasks.await(TestRepo, "t", plug: druid(["RUNNING"]), poll_interval: 5, timeout: 20)

      assert message == "timed out waiting for task t"
    end

    test "returns request errors" do
      plug = fn conn -> conn |> Plug.Conn.put_status(404) |> Plug.Conn.send_resp(404, "nope") end

      assert {:error, %Druid.Client.RequestError{status: 404}} =
               Tasks.await(TestRepo, "t", plug: plug)
    end

    test "waits for the task's segments to load" do
      plug = druid(["SUCCESS"], load: [2, 1, 0])

      assert {:ok, %{"status" => "SUCCESS"}} =
               Tasks.await(TestRepo, "t", plug: plug, poll_interval: 1, wait_for_segments: true)

      assert_received {:druid, "GET", "/druid/indexer/v1/task/t/status", _, _}

      assert_received {:druid, "GET", "/druid/coordinator/v1/datasources/events/loadstatus",
                       query, _}

      params = URI.decode_query(query)
      assert params["simple"] == "true"
      assert params["forceMetadataRefresh"] == "true"
      assert params["interval"] == "1000-01-01/3000-01-01"

      for _ <- 1..2,
          do:
            assert_received(
              {:druid, "GET", "/druid/coordinator/v1/datasources/events/" <> _, _, _}
            )

      refute_received {:druid, _, _, _, _}
    end

    test "waits for segments of another data source or interval" do
      plug = druid(["SUCCESS"])

      Tasks.await(TestRepo, "t",
        plug: plug,
        wait_for_segments: true,
        data_source: "other",
        segments_interval: "2026-11-01/P1D"
      )

      assert_received {:druid, "GET", "/druid/coordinator/v1/datasources/other/loadstatus", query,
                       _}

      assert URI.decode_query(query)["interval"] == "2026-11-01/P1D"
    end

    test "treats a data source with no used segments as loaded" do
      plug = fn
        %{path_info: [_, "coordinator" | _]} = conn ->
          Plug.Conn.send_resp(conn, 200, "No used segment found for the given datasource")

        conn ->
          druid(["SUCCESS"]).(conn)
      end

      assert {:ok, _} = Tasks.await(TestRepo, "t", plug: plug, wait_for_segments: true)
    end

    test "times out waiting for segments" do
      plug = druid(["SUCCESS"], load: [1])

      assert {:error, %Tasks.Error{reason: :timeout, status: %{"status" => "SUCCESS"}} = error} =
               Tasks.await(TestRepo, "t",
                 plug: plug,
                 wait_for_segments: true,
                 poll_interval: 5,
                 timeout: 20
               )

      assert Exception.message(error) == "timed out waiting for segments of events to load"
    end

    test "errors when there's no data source to wait for" do
      plug = druid(["SUCCESS"], status: %{"dataSource" => nil})

      assert {:error, %Tasks.Error{message: "can't wait for segments" <> _}} =
               Tasks.await(TestRepo, "t", plug: plug, wait_for_segments: true)
    end
  end

  describe "run/3" do
    test "submits and waits", %{tmp_dir: dir} do
      write!(dir, "events.json", ~s({"type": "kill", "dataSource": "events"}))

      assert {:ok, %{"id" => "task-1", "status" => "SUCCESS"}} =
               Tasks.run(TestRepo, "events", opts(dir, plug: druid(["RUNNING", "SUCCESS"])))

      assert_received {:druid, "POST", "/druid/indexer/v1/task", _, _}
      assert_received {:druid, "GET", "/druid/indexer/v1/task/task-1/status", _, _}
    end

    test "doesn't wait when submitting fails" do
      assert {:error, %Druid.Client.RequestError{}} =
               Tasks.run(TestRepo, %{"type" => "noop"}, plug: druid([], reject: true))

      assert_received {:druid, "POST", _, _, _}
      refute_received {:druid, "GET", _, _, _}
    end
  end
end
