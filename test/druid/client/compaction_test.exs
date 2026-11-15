defmodule Druid.Client.CompactionTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.Compaction

  @config "/druid/coordinator/v1/config/compaction"

  test "all/0, get/1, and delete/1" do
    assert_request(Compaction.all(), "GET", @config)
    assert_request(Compaction.get("ds"), "GET", @config <> "/ds")
    assert_request(Compaction.delete("ds"), "DELETE", @config <> "/ds")
  end

  test "set/1" do
    config = %{"dataSource" => "ds", "skipOffsetFromLatest" => "PT1H"}
    assert_request(Compaction.set(config), "POST", @config, "", config)
  end

  test "history/2" do
    assert_request(
      Compaction.history("ds", count: 5),
      "GET",
      @config <> "/ds/history",
      "count=5"
    )
  end

  test "progress/1 and status/1" do
    assert_request(
      Compaction.progress("ds"),
      "GET",
      "/druid/coordinator/v1/compaction/progress",
      "dataSource=ds"
    )

    assert_request(Compaction.status(), "GET", "/druid/coordinator/v1/compaction/status")

    assert_request(
      Compaction.status(data_source: "ds"),
      "GET",
      "/druid/coordinator/v1/compaction/status",
      "dataSource=ds"
    )
  end

  test "cluster/0 and set_cluster/1" do
    path = "/druid/indexer/v1/compaction/config/cluster"
    assert_request(Compaction.cluster(), "GET", path)

    config = %{"compactionTaskSlotRatio" => 0.5}
    assert_request(Compaction.set_cluster(config), "POST", path, "", config)
  end
end
