defmodule Druid.AwaitTelemetryTest do
  use ExUnit.Case
  import Ecto.Query
  alias Ecto.Adapters.Druid.{StatementError, TestRepo, Wikipedia}

  @events [
    [:druid, :task, :await, :start],
    [:druid, :task, :await, :stop],
    [:druid, :task, :await, :exception],
    [:druid, :statement, :await, :start],
    [:druid, :statement, :await, :stop],
    [:druid, :statement, :await, :exception]
  ]

  setup do
    start_supervised!(TestRepo)
    handler = "druid-await-telemetry-#{inspect(self())}"
    :telemetry.attach_many(handler, @events, &__MODULE__.handle_event/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  def handle_event(event, measurements, metadata, test) do
    send(test, {:telemetry, event, measurements, metadata})
  end

  # Answers each path with the response it maps to
  defp druid(responses) do
    fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)
      response = Map.fetch!(responses, {conn.method, conn.request_path})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end
  end

  defp task_status(state) do
    druid(%{
      {"GET", "/druid/indexer/v1/task/t1/status"} => %{
        "status" => %{"id" => "t1", "status" => state, "dataSource" => "events"}
      }
    })
  end

  describe "Druid.Tasks.await/3" do
    test "runs in a [:druid, :task, :await] span" do
      assert {:ok, _} = Druid.Tasks.await(TestRepo, "t1", plug: task_status("SUCCESS"))

      assert_received {:telemetry, [:druid, :task, :await, :start], _, start}
      assert %{repo: TestRepo, task_id: "t1", wait_for_segments: false} = start

      assert_received {:telemetry, [:druid, :task, :await, :stop], %{duration: _}, stop}

      assert %{
               task_id: "t1",
               state: "SUCCESS",
               data_source: "events",
               result: {:ok, %{"id" => "t1"}}
             } = stop
    end

    test "ends with :stop and the error when the task fails" do
      assert {:error, _} = Druid.Tasks.await(TestRepo, "t1", plug: task_status("FAILED"))

      assert_received {:telemetry, [:druid, :task, :await, :stop], _, stop}
      assert %{state: "FAILED", result: {:error, %Druid.Tasks.Error{reason: :failed}}} = stop
    end

    test "has no state when it times out" do
      opts = [plug: task_status("RUNNING"), timeout: 1, poll_interval: 1]
      assert {:error, _} = Druid.Tasks.await(TestRepo, "t1", opts)

      assert_received {:telemetry, [:druid, :task, :await, :stop], _, stop}
      assert %{state: nil, result: {:error, %Druid.Tasks.Error{reason: :timeout}}} = stop
    end
  end

  describe "queries from deep storage" do
    defp statement(state) do
      druid(%{
        {"POST", "/druid/v2/sql/statements"} => %{"queryId" => "q1", "state" => "RUNNING"},
        {"GET", "/druid/v2/sql/statements/q1"} => %{
          "queryId" => "q1",
          "state" => state,
          "result" => %{"numTotalRows" => 1, "pages" => [%{"id" => 0, "numRows" => 1}]}
        },
        {"GET", "/druid/v2/sql/statements/q1/results"} => [["a"]]
      })
    end

    defp opts(state) do
      [plug: statement(state), deep_storage: [poll_interval: 1], context: %{sqlQueryId: "q1"}]
    end

    test "run the statement in a [:druid, :statement, :await] span" do
      assert TestRepo.all(from(w in Wikipedia, select: w.page), opts("SUCCESS")) == ["a"]

      assert_received {:telemetry, [:druid, :statement, :await, :start], _, start}
      assert %{repo: TestRepo, query_id: "q1", timeout: 300_000} = start

      assert_received {:telemetry, [:druid, :statement, :await, :stop], %{duration: _}, stop}
      assert %{query_id: "q1", state: "SUCCESS", num_rows: 1} = stop
    end

    test "end the span with :exception when the statement fails" do
      assert_raise StatementError, fn ->
        TestRepo.all(from(w in Wikipedia, select: w.page), opts("FAILED"))
      end

      assert_received {:telemetry, [:druid, :statement, :await, :exception], _, metadata}
      assert %{query_id: "q1", kind: :error, reason: %StatementError{}} = metadata
    end
  end
end
