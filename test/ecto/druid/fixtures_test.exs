defmodule Ecto.Druid.FixturesTest do
  use ExUnit.Case, async: true
  alias Ecto.Adapters.Druid.{PageViews, TestRepo}
  alias Ecto.Druid.Fixtures

  # A fake Overlord, Coordinator and Broker. Submitted tasks are named
  # task-1, task-2, ... and succeed on their first status check, unless their
  # number is in `fail`.
  defp druid(fail) do
    test_pid = self()
    {:ok, next} = Agent.start_link(fn -> 1 end)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case {conn.method, conn.path_info} do
        {"POST", ["druid", "indexer", "v1", "task"]} ->
          n = Agent.get_and_update(next, &{&1, &1 + 1})
          send(test_pid, {:submit, Jason.decode!(body)})
          Req.Test.json(conn, %{"task" => "task-#{n}"})

        {"POST", ["druid", "indexer", "v1", "taskStatus"]} ->
          statuses =
            Map.new(Jason.decode!(body), fn "task-" <> n = id ->
              state = if String.to_integer(n) in fail, do: "FAILED", else: "SUCCESS"
              {id, %{"id" => id, "status" => state, "errorMsg" => "bad row"}}
            end)

          Req.Test.json(conn, statuses)

        {"GET", ["druid", "coordinator", "v1", "datasources", ds, "loadstatus"]} ->
          send(test_pid, {:loadstatus, ds})
          Req.Test.json(conn, %{ds => 0})

        {"POST", ["druid", "v2", "sql"]} ->
          [%{"value" => ds}] = Jason.decode!(body)["parameters"]
          send(test_pid, {:broker_lists, ds})
          Req.Test.json(conn, [[1]])
      end
    end
  end

  defp load!(fixtures, fail \\ []),
    do: Fixtures.load!(TestRepo, fixtures, plug: druid(fail), poll_interval: 1)

  test "ingests a schema's rows with its dataSchema, replacing the data source" do
    rows = [
      %{"ts" => 1_466_989_200_000, "country" => "US", "user_key" => "a"},
      %{"ts" => 1_466_992_800_000, "country" => "CA", "user_key" => "b"}
    ]

    assert load!([{PageViews, rows}]) == :ok

    assert_received {:submit, %{"type" => "index_parallel", "spec" => spec}}
    assert spec["ioConfig"]["appendToExisting"] == false
    assert spec["ioConfig"]["dropExisting"] == true
    assert spec["ioConfig"]["inputFormat"] == %{"type" => "json"}

    assert spec["ioConfig"]["inputSource"] == %{
             "type" => "inline",
             "data" => Enum.map_join(rows, "\n", &Jason.encode!/1)
           }

    data_schema = Ecto.Druid.Schema.Spec.data_schema(PageViews, segment_granularity: "DAY")

    assert Map.delete(spec["dataSchema"], "granularitySpec") ==
             Map.delete(data_schema, "granularitySpec")

    assert spec["dataSchema"]["granularitySpec"] ==
             Map.put(data_schema["granularitySpec"], "intervals", ["1000-01-01/3000-01-01"])

    # Waits until the data can be queried
    assert_received {:loadstatus, "ecto_druid_page_views_test"}
    assert_received {:broker_lists, "ecto_druid_page_views_test"}
  end

  @tag :tmp_dir
  test "loads a data source by name, from a file, with several at once", %{tmp_dir: dir} do
    path = Path.join(dir, "events.csv")
    File.write!(path, "timestamp,page\n2016-06-27T01:00:00Z,Main\n")
    csv = %{"type" => "csv", "findColumnsFromHeader" => true}

    data_schema = %{
      timestampSpec: %{column: "timestamp", format: "iso"},
      dimensionsSpec: %{dimensions: ["page"]},
      granularitySpec: %{segmentGranularity: "HOUR"}
    }

    fixtures = [
      {"events", path, data_schema: data_schema, input_format: csv},
      {PageViews, [%{"ts" => 0}], data_source: "page_views", segment_granularity: "HOUR"}
    ]

    assert load!(fixtures) == :ok

    assert_received {:submit, %{"spec" => events}}
    assert events["ioConfig"]["inputSource"]["data"] == File.read!(path)
    assert events["ioConfig"]["inputFormat"] == csv

    assert events["dataSchema"] == %{
             "dataSource" => "events",
             "timestampSpec" => %{"column" => "timestamp", "format" => "iso"},
             "dimensionsSpec" => %{"dimensions" => ["page"]},
             "granularitySpec" => %{
               "segmentGranularity" => "HOUR",
               "intervals" => ["1000-01-01/3000-01-01"]
             }
           }

    assert_received {:submit, %{"spec" => %{"dataSchema" => page_views}}}
    assert page_views["dataSource"] == "page_views"
    assert page_views["granularitySpec"]["segmentGranularity"] == "HOUR"

    assert_received {:broker_lists, "events"}
    assert_received {:broker_lists, "page_views"}
  end

  test "raises naming the data sources whose tasks failed" do
    fixtures = [{"events", [%{"a" => 1}], data_schema: %{}}, {PageViews, [%{"ts" => 0}]}]

    error = assert_raise Druid.Tasks.Error, fn -> load!(fixtures, [2]) end
    assert error.message =~ "couldn't load fixtures into ecto_druid_page_views_test: "
    assert error.message =~ "bad row"
    refute error.message =~ "events"
    assert error.reason == :failed
    assert error.task_id == "task-2"
  end

  test "raises on fixtures it can't load, before submitting anything" do
    assert_raise ArgumentError,
                 ~r/more than one fixture loads into: ecto_druid_page_views_test/,
                 fn ->
                   load!([{PageViews, [%{"ts" => 0}]}, {PageViews, [%{"ts" => 1}]}])
                 end

    assert_raise ArgumentError, ~r/PageViews fixture has no rows/, fn ->
      load!([{PageViews, []}])
    end

    assert_raise ArgumentError, ~r/events fixture needs a :data_schema option/, fn ->
      load!([{"events", [%{"a" => 1}]}])
    end

    assert_raise ArgumentError, ~r/to use Ecto.Druid.Schema/, fn ->
      load!([{URI, [%{"a" => 1}]}])
    end

    assert_raise ArgumentError, ~r/expected a fixture as/, fn -> load!([PageViews]) end

    refute_received {:submit, _}
  end

  # A fake Druid for drop!/3. Each data source has a running task,
  # running-<name>, until it's shut down, and the Broker lists it until its
  # kill task succeeds. Kill tasks are named kill-<name>, and fail when the
  # data source is in `fail`. Every request is sent to the test process with
  # the port it went to.
  defp drop_druid(opts) do
    test_pid = self()
    fail = Keyword.get(opts, :fail, [])
    listed = Keyword.get(opts, :listed, :until_killed)
    {:ok, state} = Agent.start_link(fn -> %{shut_down: MapSet.new(), killed: MapSet.new()} end)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      conn = Plug.Conn.fetch_query_params(conn)
      send(test_pid, {:request, conn.port, conn.method, conn.request_path})

      case {conn.method, conn.path_info} do
        {"GET", ["druid", "indexer", "v1", "tasks"]} ->
          %{"state" => task_state, "datasource" => ds} = conn.query_params
          shut_down = Agent.get(state, & &1.shut_down)
          active = task_state == "running" and not MapSet.member?(shut_down, ds)
          Req.Test.json(conn, if(active, do: [%{"id" => "running-#{ds}"}], else: []))

        {"POST", ["druid", "indexer", "v1", "task", "running-" <> ds, "shutdown"]} ->
          Agent.update(state, &update_in(&1.shut_down, fn s -> MapSet.put(s, ds) end))
          Req.Test.json(conn, %{"task" => "running-#{ds}"})

        {"DELETE", ["druid", "indexer", "v1", "datasources", _ds]} ->
          Req.Test.json(conn, %{"numChangedSegments" => 1})

        {"POST", ["druid", "indexer", "v1", "task"]} ->
          %{"dataSource" => ds} = task = Jason.decode!(body)
          send(test_pid, {:submit, task})
          Req.Test.json(conn, %{"task" => "kill-#{ds}"})

        {"GET", ["druid", "indexer", "v1", "task", "kill-" <> ds = id, "status"]} ->
          status = if ds in fail, do: "FAILED", else: "SUCCESS"

          if status == "SUCCESS",
            do: Agent.update(state, &update_in(&1.killed, fn s -> MapSet.put(s, ds) end))

          Req.Test.json(conn, %{
            "status" => %{"id" => id, "status" => status, "errorMsg" => "boom"}
          })

        {"POST", ["druid", "v2", "sql"]} ->
          [%{"value" => ds}] = Jason.decode!(body)["parameters"]
          killed = Agent.get(state, &MapSet.member?(&1.killed, ds))
          listed? = listed == :always or (listed == :until_killed and not killed)
          Req.Test.json(conn, if(listed?, do: [[1]], else: []))
      end
    end
  end

  defp drop!(data_sources, opts \\ []) do
    Fixtures.drop!(TestRepo, data_sources, [plug: drop_druid(opts), poll_interval: 1] ++ opts)
  end

  defp requests do
    receive do
      {:request, port, method, path} -> [{port, method, path} | requests()]
    after
      0 -> []
    end
  end

  describe "drop!/3" do
    test "shuts down tasks, marks segments unused, kills them, and waits for the Broker" do
      assert drop!("events_test") == :ok

      assert_received {:submit,
                       %{
                         "type" => "kill",
                         "dataSource" => "events_test",
                         "interval" =>
                           "-146136543-09-08T08:23:32.096Z/146140482-04-24T15:36:27.903Z"
                       }}

      # In this order, so no task is left to publish segments after the kill.
      # Tasks and segments go to the :tasks host, SQL to the repo's own.
      assert requests() |> Enum.reject(&match?({_, "GET", "/druid/indexer/v1/tasks"}, &1)) == [
               {9888, "POST", "/druid/indexer/v1/task/running-events_test/shutdown"},
               {9888, "DELETE", "/druid/indexer/v1/datasources/events_test"},
               {9888, "POST", "/druid/indexer/v1/task"},
               {9888, "GET", "/druid/indexer/v1/task/kill-events_test/status"},
               {9082, "POST", "/druid/v2/sql"}
             ]
    end

    test "drops each of a list of data sources" do
      assert drop!(["events_test", "edits_test"]) == :ok

      assert_received {:submit, %{"dataSource" => "events_test"}}
      assert_received {:submit, %{"dataSource" => "edits_test"}}
      assert_received {:request, _, "POST", "/druid/indexer/v1/task/running-edits_test/shutdown"}
      assert_received {:request, _, "DELETE", "/druid/indexer/v1/datasources/edits_test"}
    end

    test "raises when a kill task fails" do
      error =
        assert_raise Druid.Tasks.Error, fn -> drop!("events_test", fail: ["events_test"]) end

      assert error.message =~ "couldn't drop events_test"
      assert error.message =~ "boom"
      assert error.reason == :failed
      assert error.task_id == "kill-events_test"
    end

    test "raises when the Broker still lists a data source at the timeout" do
      error =
        assert_raise Druid.Tasks.Error, fn ->
          drop!("events_test", listed: :always, timeout: 50)
        end

      assert error.message =~ "Broker to stop listing events_test"
      assert error.reason == :timeout
    end

    test "raises when Druid can't be reached" do
      plug = fn conn -> Req.Test.transport_error(conn, :econnrefused) end

      error =
        assert_raise Druid.Tasks.Error, fn ->
          Fixtures.drop!(TestRepo, "events_test", plug: plug, retry: false)
        end

      assert error.message =~ "couldn't drop events_test"
    end

    test "takes data source names only" do
      assert_raise ArgumentError, ~r/expected a data source name, got: .*PageViews/, fn ->
        drop!(PageViews)
      end

      refute_received {:request, _, _, _}
    end
  end
end
