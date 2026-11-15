defmodule Druid.Client.MetadataTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.Metadata

  @v1 "/druid/coordinator/v1"

  test "data_sources/1" do
    assert_request(Metadata.data_sources(), "GET", @v1 <> "/metadata/datasources")

    assert_request(
      Metadata.data_sources(include_unused: true, full: true),
      "GET",
      @v1 <> "/metadata/datasources",
      "includeUnused=true&full=true"
    )
  end

  test "data_source/1" do
    assert_request(Metadata.data_source("ds"), "GET", @v1 <> "/metadata/datasources/ds")
  end

  test "segments/1 repeats datasources" do
    assert_request(
      Metadata.segments(data_sources: ["a", "b"], include_overshadowed_status: true),
      "GET",
      @v1 <> "/metadata/segments",
      "datasources=a&datasources=b&includeOvershadowedStatus=true"
    )
  end

  test "data_source_segments/2 and segment/3" do
    assert_request(
      Metadata.data_source_segments("ds", full: true),
      "GET",
      @v1 <> "/metadata/datasources/ds/segments",
      "full=true"
    )

    assert_request(
      Metadata.segment("ds", "seg_1", include_unused: true),
      "GET",
      @v1 <> "/metadata/datasources/ds/segments/seg_1",
      "includeUnused=true"
    )
  end

  test "load_status/1, load_queue/1, and servers/1" do
    assert_request(Metadata.load_status(simple: true), "GET", @v1 <> "/loadstatus", "simple=true")
    assert_request(Metadata.load_queue(full: true), "GET", @v1 <> "/loadqueue", "full=true")
    assert_request(Metadata.servers(simple: true), "GET", @v1 <> "/servers", "simple=true")
  end
end
