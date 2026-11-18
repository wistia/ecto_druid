defmodule StreamingIntegrationTest do
  # Writes to the compose file's Kafka with `docker compose exec`, so it needs
  # the stack from docker-compose.yml, not only a Druid.
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Adapters.Druid.IntegrationRepo

  @moduletag timeout: 600_000

  @id "ecto_druid_streaming_test"
  @topic "ecto_druid_streaming_test"

  setup do
    router = [host: "localhost", port: IntegrationRepo.config()[:supervisors][:port]]

    kafka!([
      "/opt/kafka/bin/kafka-topics.sh",
      "--bootstrap-server",
      "kafka:9092",
      "--create",
      "--if-not-exists",
      "--topic",
      @topic,
      "--partitions",
      "2"
    ])

    on_exit(fn ->
      # Forget the stored offsets too, so a later run starts from the end of
      # the topic even if it was recreated
      for request <- [
            Druid.Client.Supervisor.reset(@id),
            Druid.Client.Supervisor.terminate(@id),
            Druid.Client.DataSource.mark_unused(@id)
          ],
          do: Druid.Client.request(request, router)
    end)

    %{router: router}
  end

  test "waits for the tasks to read, then hands their segments off", %{router: router} do
    Druid.Client.Supervisor.submit(spec()) |> Druid.Client.request!(router)

    assert {:ok, %{"state" => "RUNNING", "activeTasks" => [_]}} =
             Druid.Supervisors.await_running(IntegrationRepo, @id,
               timeout: 180_000,
               poll_interval: 1_000
             )

    # The spec starts from the end of the topic, so these are only ingested
    # because the task is already reading
    run = "run-#{System.unique_integer([:positive])}"
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    produce!([
      %{timestamp: now, run: run, channel: "#en"},
      %{timestamp: now, run: run, channel: "#fr"}
    ])

    assert eventually(fn -> rows(run) end, 60_000) == [{"#en", 1}, {"#fr", 1}]

    assert {:ok, [%{"status" => "SUCCESS", "dataSource" => @id}]} =
             Druid.Supervisors.handoff(IntegrationRepo, @id,
               wait_for_segments: true,
               timeout: 300_000,
               poll_interval: 1_000
             )

    # Served by the Historical now: the task that read them has finished
    assert rows(run) == [{"#en", 1}, {"#fr", 1}]

    load_status =
      Druid.Client.DataSource.load_status(@id, simple: true, force_metadata_refresh: true)
      |> Druid.Client.request!(router)

    assert load_status == %{@id => 0}
  end

  defp spec do
    %{
      "type" => "kafka",
      "spec" => %{
        "ioConfig" => %{
          "type" => "kafka",
          "topic" => @topic,
          "consumerProperties" => %{"bootstrap.servers" => "kafka:9092"},
          "inputFormat" => %{"type" => "json"},
          "taskCount" => 1,
          "taskDuration" => "PT1H",
          "useEarliestOffset" => false
        },
        "tuningConfig" => %{"type" => "kafka"},
        "dataSchema" => %{
          "dataSource" => @id,
          "timestampSpec" => %{"column" => "timestamp", "format" => "iso"},
          "dimensionsSpec" => %{"dimensions" => ["run", "channel"]},
          "metricsSpec" => [%{"type" => "count", "name" => "count"}],
          "granularitySpec" => %{
            "segmentGranularity" => "HOUR",
            "queryGranularity" => "NONE",
            "rollup" => true
          }
        }
      }
    }
  end

  defp rows(run) do
    IntegrationRepo.all(
      from e in @id,
        where: e.run == ^run,
        group_by: e.channel,
        order_by: e.channel,
        select: {e.channel, sum(e.count)}
    )
  end

  defp produce!(messages) do
    lines = Enum.map_join(messages, "\n", &Jason.encode!/1)

    producer =
      "/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic #{@topic}"

    {output, status} =
      System.cmd(
        "sh",
        ["-c", "printf '%s\\n' \"$0\" | docker compose exec -T kafka #{producer}", lines],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp kafka!(args) do
    {output, status} =
      System.cmd("docker", ["compose", "exec", "-T", "kafka" | args], stderr_to_stdout: true)

    assert status == 0, output
  end

  # Calls `fun` until it returns a non-empty list, for up to `timeout` ms.
  # The query fails until the data source exists.
  defp eventually(fun, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    eventually_until(fun, deadline)
  end

  defp eventually_until(fun, deadline) do
    result =
      try do
        fun.()
      rescue
        _ -> []
      end

    if result == [] and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(1_000)
      eventually_until(fun, deadline)
    else
      result
    end
  end
end
