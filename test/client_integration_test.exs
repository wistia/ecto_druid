defmodule ClientIntegrationTest do
  use ExUnit.Case

  @moduletag :druid

  alias Druid.Client
  alias Druid.Client.{Compaction, Config, DataSource, Metadata, Status, Supervisor, Task}

  @router [host: "localhost", port: 9888]
  @broker [host: "localhost", port: 9082]

  defp ok!(req, opts \\ @router) do
    assert {:ok, body} = Client.request(req, opts)
    body
  end

  test "reads service status" do
    assert ok!(Status.health()) == true
    assert %{"version" => _} = ok!(Status.get())
    assert %{"selfDiscovered" => true} = ok!(Status.self_discovered())
    assert "http" <> _ = ok!(Status.leader(:coordinator))
    assert "http" <> _ = ok!(Status.leader(:overlord))
    assert is_list(ok!(Status.workers()))
    assert %{"inventoryInitialized" => _} = ok!(Status.load_status(:broker), @broker)
  end

  test "reads dynamic and compaction config" do
    assert %{"maxSegmentsToMove" => _} = ok!(Config.get(:coordinator))
    assert %{"queryBlocklist" => _} = ok!(Config.get(:broker))
    assert is_list(ok!(Config.history(:coordinator, count: 1)))
    assert %{"compactionConfigs" => _} = ok!(Compaction.all())
    assert %{"compactionTaskSlotRatio" => _} = ok!(Compaction.cluster())
    assert %{"latestStatus" => _} = ok!(Compaction.statuses())
  end

  test "lists tasks, supervisors, data sources, and segments" do
    assert is_list(ok!(Task.all(state: "complete", max: 1)))
    assert is_list(ok!(Task.running()))
    assert ok!(Task.statuses(["ecto_druid_missing_task"])) == %{}
    assert is_list(ok!(Supervisor.list(state: true)))
    assert is_map(ok!(Supervisor.history()))
    assert is_list(ok!(DataSource.list(simple: true)))
    assert is_list(ok!(Metadata.data_sources(include_unused: true)))
    assert is_map(ok!(Metadata.load_queue(simple: true)))
    assert is_list(ok!(Metadata.servers(simple: true)))
  end
end
