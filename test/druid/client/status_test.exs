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

  describe "retries" do
    defp attempts(request, opts \\ []) do
      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      plug = fn conn ->
        Agent.update(attempts, &(&1 + 1))
        Plug.Conn.send_resp(conn, 503, "")
      end

      opts =
        Keyword.merge(
          [plug: plug, host: "localhost", port: 1, retry_delay: 0, retry_log_level: false],
          opts
        )

      assert {:error, %{status: 503}} = Druid.Client.request(request, opts)
      Agent.get(attempts, & &1)
    end

    test "checks report a 503 at once" do
      for request <- [
            Status.health(),
            Status.self_discovered(),
            Status.readiness(:broker),
            Status.readiness(:historical),
            Status.load_status(:broker),
            Status.load_status(:historical)
          ] do
        assert attempts(request) == 1
      end
    end

    test "checks can opt back into retries" do
      assert attempts(Status.readiness(:broker), retry: :safe_transient) == 4
    end

    test "other requests are retried" do
      assert attempts(Status.get()) == 4
    end
  end

  test "workers/0 and scaling/0" do
    assert_request(Status.workers(), "GET", "/druid/indexer/v1/workers")
    assert_request(Status.scaling(), "GET", "/druid/indexer/v1/scaling")
  end
end
