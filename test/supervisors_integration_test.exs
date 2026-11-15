defmodule SupervisorsIntegrationTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo

  @druid [host: "localhost", port: 9888]
  @kafka_id "ecto_druid_supervisors_test"
  @schema_id "ecto_druid_page_views_test"
  @compaction_id "autocompact__ecto_druid_page_views_test"

  setup do
    on_exit(fn ->
      for id <- [@kafka_id, @schema_id, @compaction_id] do
        Druid.Client.Supervisor.terminate(id) |> Druid.Client.request(@druid)
      end
    end)
  end

  defp get!(id), do: Druid.Client.Supervisor.get(id) |> Druid.Client.request!(@druid)

  test "creates, leaves unchanged, and updates a supervisor" do
    sync = &Druid.Supervisors.sync(TestRepo, [only: [@kafka_id]] ++ &1)

    assert [{:would_create, %{id: @kafka_id}}] = sync.(dry_run: true)
    assert [{:created, %{id: @kafka_id}}] = sync.([])
    assert [{:unchanged, %{id: @kafka_id}}] = sync.([])
    assert [{:updated, %{id: @kafka_id}}] = sync.(specs: %{@kafka_id => %{task_count: 2}})

    current = get!(@kafka_id)
    assert current["spec"]["ioConfig"]["taskCount"] == 2
    assert current["suspended"] == true
  end

  test "Druid accepts specs generated from an Ecto.Druid.Schema" do
    names = [@schema_id, @schema_id <> ".compaction"]

    # Results follow template file order
    assert [{:created, %{id: @compaction_id}}, {:created, %{id: @schema_id}}] =
             Druid.Supervisors.sync(TestRepo, only: names)

    assert [{:unchanged, _}, {:unchanged, _}] = Druid.Supervisors.sync(TestRepo, only: names)

    data_schema = get!(@schema_id)["spec"]["dataSchema"]
    assert data_schema["timestampSpec"]["column"] == "ts"
    assert data_schema["timestampSpec"]["format"] == "millis"

    assert Enum.map(data_schema["dimensionsSpec"]["dimensions"], & &1["name"]) ==
             ["country", "browser_name", "tags", "duration_ms", "attributes"] ++
               ["visitor_key", "user_agent", "referrer"]

    assert data_schema["transformSpec"]["transforms"] == [
             %{"type" => "expression", "name" => "visitor_key", "expression" => ~s("user_key")},
             %{"type" => "expression", "name" => "user_agent", "expression" => ~s("user-agent")}
           ]

    assert data_schema["transformSpec"]["filter"]["type"] == "not"

    assert Enum.map(data_schema["metricsSpec"], &{&1["type"], &1["name"]}) == [
             {"count", "views"},
             {"doubleSum", "watch_time"},
             {"longMax", "max_duration"},
             {"thetaSketch", "sessions"},
             {"HLLSketchBuild", "visitors"},
             {"quantilesDoublesSketch", "load_times"},
             {"fixedBucketsHistogram", "scroll_depth"}
           ]

    compaction = get!(@compaction_id)["spec"]

    assert Enum.map(compaction["metricsSpec"], &{&1["type"], &1["fieldName"]}) == [
             {"longSum", "views"},
             {"doubleSum", "watch_time"},
             {"longMax", "max_duration"},
             {"thetaSketch", "sessions"},
             {"HLLSketchMerge", "visitors"},
             {"quantilesDoublesSketch", "load_times"},
             {"fixedBucketsHistogram", "scroll_depth"}
           ]
  end
end
