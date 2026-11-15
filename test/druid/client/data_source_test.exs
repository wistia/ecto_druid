defmodule Druid.Client.DataSourceTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.DataSource

  @coordinator "/druid/coordinator/v1/datasources"
  @overlord "/druid/indexer/v1/datasources"

  test "list/1" do
    assert_request(DataSource.list(), "GET", @coordinator)
    assert_request(DataSource.list(simple: true), "GET", @coordinator, "simple=true")
    assert_request(DataSource.list(full: true), "GET", @coordinator, "full=true")
  end

  test "get/2 escapes the data source" do
    assert_request(DataSource.get("my/ds"), "GET", @coordinator <> "/my%2Fds")
    assert_request(DataSource.get("ds", full: true), "GET", @coordinator <> "/ds", "full=true")
  end

  test "intervals/2" do
    assert_request(
      DataSource.intervals("ds", simple: true),
      "GET",
      @coordinator <> "/ds/intervals",
      "simple=true"
    )
  end

  test "interval/3 uses Druid's path interval format" do
    assert_request(
      DataSource.interval("ds", "2015-09-12T00:00:00Z/2015-09-13T00:00:00Z", full: true),
      "GET",
      @coordinator <> "/ds/intervals/2015-09-12T00%3A00%3A00Z_2015-09-13T00%3A00%3A00Z",
      "full=true"
    )
  end

  test "segments/2 and segment/2" do
    assert_request(DataSource.segments("ds"), "GET", @coordinator <> "/ds/segments")
    assert_request(DataSource.segment("ds", "seg_1"), "GET", @coordinator <> "/ds/segments/seg_1")
  end

  test "tiers/1" do
    assert_request(DataSource.tiers("ds"), "GET", @coordinator <> "/ds/tiers")
  end

  test "load_status/2 always sends forceMetadataRefresh" do
    assert_request(
      DataSource.load_status("ds"),
      "GET",
      @coordinator <> "/ds/loadstatus",
      "forceMetadataRefresh=false"
    )

    assert_request(
      DataSource.load_status("ds",
        force_metadata_refresh: true,
        interval: "2015-09-12/2015-09-13",
        simple: true
      ),
      "GET",
      @coordinator <> "/ds/loadstatus",
      "forceMetadataRefresh=true&interval=2015-09-12%2F2015-09-13&simple=true"
    )
  end

  test "mark_used/2" do
    assert_request(DataSource.mark_used("ds"), "POST", @overlord <> "/ds")

    selector = %{"interval" => "2015-09-12/2015-09-13"}

    assert_request(
      DataSource.mark_used("ds", selector),
      "POST",
      @overlord <> "/ds/markUsed",
      "",
      selector
    )
  end

  test "mark_unused/2" do
    assert_request(DataSource.mark_unused("ds"), "DELETE", @overlord <> "/ds")

    selector = %{"segmentIds" => ["seg_1"]}

    assert_request(
      DataSource.mark_unused("ds", selector),
      "POST",
      @overlord <> "/ds/markUnused",
      "",
      selector
    )
  end

  test "mark_segment_used/2 and mark_segment_unused/2" do
    assert_request(
      DataSource.mark_segment_used("ds", "seg_1"),
      "POST",
      @overlord <> "/ds/segments/seg_1"
    )

    assert_request(
      DataSource.mark_segment_unused("ds", "seg_1"),
      "DELETE",
      @overlord <> "/ds/segments/seg_1"
    )
  end

  test "kill/2" do
    assert_request(
      DataSource.kill("ds", "2015-09-12/2015-09-13"),
      "DELETE",
      @coordinator <> "/ds/intervals/2015-09-12_2015-09-13"
    )
  end
end
