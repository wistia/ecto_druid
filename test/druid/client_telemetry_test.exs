defmodule Druid.ClientTelemetryTest do
  use ExUnit.Case
  alias Druid.Client.RequestError
  alias Ecto.Adapters.Druid.TestRepo

  @events [
    [:druid, :request, :start],
    [:druid, :request, :stop],
    [:druid, :request, :exception]
  ]

  setup do
    handler = "druid-client-telemetry-#{inspect(self())}"
    :telemetry.attach_many(handler, @events, &__MODULE__.handle_event/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  def handle_event(event, measurements, metadata, test) do
    send(test, {:telemetry, event, measurements, metadata})
  end

  defp respond(status, body) do
    fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end
  end

  @druid [host: "druid.test", port: 8888]

  test "wraps each request in a [:druid, :request] span" do
    Druid.Client.Task.status("t1")
    |> Druid.Client.request!([plug: respond(200, %{"status" => %{}})] ++ @druid)

    assert_received {:telemetry, [:druid, :request, :start], %{system_time: _}, start}

    assert Map.delete(start, :telemetry_span_context) == %{
             method: :get,
             scheme: "http",
             host: "druid.test",
             port: 8888,
             path: "/druid/indexer/v1/task/t1/status"
           }

    assert_received {:telemetry, [:druid, :request, :stop], measurements, stop}
    assert %{duration: duration, decode_time: decode_time} = measurements
    assert duration >= decode_time
    assert stop.status == 200
    assert Map.delete(stop, :status) == start
  end

  test "ends with :stop and the status when Druid responds with an error" do
    assert_raise RequestError, fn ->
      Druid.Client.Task.status("t1")
      |> Druid.Client.request!([plug: respond(404, %{"error" => "no"})] ++ @druid)
    end

    assert_received {:telemetry, [:druid, :request, :stop], _, %{status: 404}}
    refute_received {:telemetry, [:druid, :request, :exception], _, _}
  end

  test "ends with :exception when no response comes back" do
    plug = fn conn -> Req.Test.transport_error(conn, :timeout) end

    # A POST, which Req doesn't retry
    assert {:error, %Req.TransportError{reason: :timeout}} =
             Druid.Client.Task.submit(%{}) |> Druid.Client.request([plug: plug] ++ @druid)

    assert_received {:telemetry, [:druid, :request, :exception], %{duration: _}, metadata}

    assert %{kind: :error, reason: %Req.TransportError{}, path: "/druid/indexer/v1/task"} =
             metadata
  end

  test "merges :telemetry_metadata and leaves credentials out" do
    opts = [
      plug: respond(200, []),
      auth: {:basic, "user:secret"},
      telemetry_metadata: %{tag: :mine}
    ]

    Druid.Client.Task.all() |> Druid.Client.request!(opts ++ @druid)

    assert_received {:telemetry, [:druid, :request, :stop], _, metadata}
    assert metadata.tag == :mine
    refute inspect(metadata) =~ "secret"
  end

  describe "repo requests" do
    setup do
      start_supervised!(TestRepo)
      :ok
    end

    test "carry the repo" do
      TestRepo.all(Ecto.Adapters.Druid.Wikipedia, plug: respond(200, []))

      assert_received {:telemetry, [:druid, :request, :stop], _,
                       %{repo: TestRepo, path: "/druid/v2/sql", method: :post}}
    end

    test "from Druid.Tasks carry the repo" do
      Druid.Tasks.await(TestRepo, "t1",
        plug: respond(200, %{"status" => %{"status" => "SUCCESS"}})
      )

      assert_received {:telemetry, [:druid, :request, :stop], _, %{repo: TestRepo}}
    end
  end
end
