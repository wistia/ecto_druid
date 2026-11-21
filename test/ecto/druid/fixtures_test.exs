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
end
