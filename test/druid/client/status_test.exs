defmodule Druid.Client.StatusTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.Status

  test "service endpoints" do
    assert_request(Status.get(), "GET", "/status")
    assert_request(Status.health(), "GET", "/status/health")
    assert_request(Status.properties(), "GET", "/status/properties")
    assert_request(Status.self_discovered(), "GET", "/status/selfDiscovered/status")
  end

  test "leader/1" do
    assert_request(Status.leader(:coordinator), "GET", "/druid/coordinator/v1/leader")
    assert_request(Status.leader(:overlord), "GET", "/druid/indexer/v1/leader")
  end

  test "readiness/1 and load_status/1" do
    assert_request(Status.readiness(:broker), "GET", "/druid/broker/v1/readiness")
    assert_request(Status.readiness(:historical), "GET", "/druid/historical/v1/readiness")
    assert_request(Status.load_status(:broker), "GET", "/druid/broker/v1/loadstatus")
    assert_request(Status.load_status(:historical), "GET", "/druid/historical/v1/loadstatus")
  end

  test "workers/0 and scaling/0" do
    assert_request(Status.workers(), "GET", "/druid/indexer/v1/workers")
    assert_request(Status.scaling(), "GET", "/druid/indexer/v1/scaling")
  end
end
