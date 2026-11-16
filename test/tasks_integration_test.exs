defmodule TasksIntegrationTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_tasks_test"
  @task "ecto_druid_tasks_test"

  # Ingestion tasks take a while to start and finish in the test cluster
  @moduletag timeout: 300_000

  setup do
    on_exit(fn ->
      Druid.Client.DataSource.mark_unused(@data_source) |> Druid.Client.request(@druid)
    end)
  end

  defp row(attrs) do
    Map.merge(
      %{
        "ts" => 1_793_491_200_000,
        "country" => "US",
        "user_key" => "u1",
        "visitor_id" => "v1",
        "session_id" => "s1",
        "watch_seconds" => 1.5,
        "duration_ms" => 10,
        "load_ms" => 100,
        "scroll_pct" => 50
      },
      attrs
    )
  end

  test "runs a batch ingestion task from a template and waits for its segments" do
    rows = [row(%{"country" => "US"}), row(%{"country" => "CA"})]

    assert {:ok, %{"status" => "SUCCESS", "dataSource" => @data_source}} =
             Druid.Tasks.run(TestRepo, @task,
               assigns: %{rows: rows},
               wait_for_segments: true,
               timeout: 240_000
             )

    # The segments are loaded, so the rows can be queried right away
    assert [[2]] =
             Druid.Client.SQL.query(~s[SELECT COUNT(*) FROM "#{@data_source}"])
             |> Druid.Client.request!(@druid)
  end

  test "returns an error when the task fails" do
    rows = [row(%{"ts" => "not a timestamp"})]

    assert {:error, %Druid.Tasks.Error{reason: :failed, task_id: task_id}} =
             Druid.Tasks.run(TestRepo, @task, assigns: %{rows: rows}, timeout: 240_000)

    assert is_binary(task_id)
  end

  test "waits for a SQL-based ingestion query" do
    sql = """
    INSERT INTO "#{@data_source}"
    SELECT TIMESTAMP '2026-11-01 00:00:00' AS __time, 'US' AS country
    FROM (VALUES (1), (2), (3)) AS t (n)
    PARTITIONED BY DAY
    """

    %{"taskId" => task_id} = Druid.Client.SQL.insert(sql) |> Druid.Client.request!(@druid)

    assert {:ok, %{"status" => "SUCCESS"}} =
             Druid.Tasks.await(TestRepo, task_id,
               wait_for_segments: true,
               data_source: @data_source,
               timeout: 240_000
             )

    assert [[3]] =
             Druid.Client.SQL.query(~s[SELECT COUNT(*) FROM "#{@data_source}"])
             |> Druid.Client.request!(@druid)
  end
end
