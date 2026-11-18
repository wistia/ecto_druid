defmodule TasksIntegrationTest do
  use ExUnit.Case, async: true
  alias Ecto.Adapters.Druid.IntegrationRepo

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
             Druid.Tasks.run(IntegrationRepo, @task,
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
             Druid.Tasks.run(IntegrationRepo, @task, assigns: %{rows: rows}, timeout: 240_000)

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
             Druid.Tasks.await(IntegrationRepo, task_id,
               wait_for_segments: true,
               data_source: @data_source,
               timeout: 240_000
             )

    assert [[3]] =
             Druid.Client.SQL.query(~s[SELECT COUNT(*) FROM "#{@data_source}"])
             |> Druid.Client.request!(@druid)
  end

  defp count_by_day do
    ~s[SELECT TIME_FLOOR(__time, 'P1D') AS d, COUNT(*) FROM "#{@data_source}" GROUP BY 1 ORDER BY 1]
    |> Druid.Client.SQL.query()
    |> Druid.Client.request!(@druid)
    |> Enum.map(fn [day, count] -> {String.slice(day, 0, 10), count} end)
  end

  test "backfills one task per day, replacing only each task's interval" do
    day = fn date, n ->
      row(%{
        "ts" => DateTime.to_unix(DateTime.new!(date, ~T[12:00:00]), :millisecond),
        "user_key" => "u#{n}"
      })
    end

    rows = [day.(~D[2026-11-01], 1), day.(~D[2026-11-01], 2), day.(~D[2026-11-02], 3)]

    runs =
      Druid.Tasks.backfill(IntegrationRepo, @task, ~D[2026-11-01], ~D[2026-11-03],
        assigns: %{rows: rows},
        concurrency: 1,
        wait_for_segments: true,
        timeout: 240_000
      )

    assert [%{error: nil}, %{error: nil}] = runs
    assert count_by_day() == [{"2026-11-01", 2}, {"2026-11-02", 1}]

    # Each task only ingests its own interval of the input, so rerunning one
    # day replaces that day and leaves the other alone
    rows = [day.(~D[2026-11-01], 9), day.(~D[2026-11-02], 4), day.(~D[2026-11-02], 5)]

    assert [%{error: nil}] =
             Druid.Tasks.backfill(IntegrationRepo, @task, ~D[2026-11-02], ~D[2026-11-03],
               assigns: %{rows: rows},
               wait_for_segments: true,
               timeout: 240_000
             )

    assert count_by_day() == [{"2026-11-01", 2}, {"2026-11-02", 2}]
  end
end
