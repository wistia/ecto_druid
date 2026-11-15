defmodule Mix.Tasks.WikiExplorer.Ingest do
  @shortdoc "Loads the sample Wikipedia edits into Druid"

  @moduledoc """
  Submits a batch ingestion task for the `wiki_edits` data source and waits
  until it can be queried.

      mix wiki_explorer.ingest

  Druid downloads the data (about 24,000 edits from 2016-06-27) from
  druid.apache.org, so the Druid container needs internet access. Running the
  task again replaces the data.

  The task's `dataSchema` (timestamp, dimensions and metrics) is generated
  from `WikiExplorer.Wiki.Edit` with `Ecto.Druid.Schema.Spec.data_schema/2`.
  It uses `Druid.Client` with the repo's config as connection options.
  """
  use Mix.Task

  alias Druid.Client
  alias Ecto.Druid.Schema.Spec
  alias WikiExplorer.DruidRepo
  alias WikiExplorer.Wiki.Edit

  @poll_ms 2_000
  @timeout_ms 300_000

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)
    druid = DruidRepo.config()

    %{"task" => task_id} = ingestion_task() |> Client.Task.submit() |> Client.request!(druid)
    Mix.shell().info("Submitted ingestion task #{task_id}")

    wait("ingestion task", fn ->
      %{"status" => %{"status" => status} = task} =
        task_id |> Client.Task.status() |> Client.request!(druid)

      case status do
        "SUCCESS" -> :done
        "FAILED" -> Mix.raise("Ingestion failed: #{task["errorMsg"]}")
        _running -> :wait
      end
    end)

    # Segments are queryable once a Historical has loaded them, shortly after
    # the task succeeds.
    wait("segments to load", fn ->
      case Client.SQL.query("SELECT COUNT(*) FROM wiki_edits") |> Client.request(druid) do
        {:ok, [[count]]} when count > 0 -> {:done, count}
        _ -> :wait
      end
    end)
  end

  defp ingestion_task do
    %{
      "type" => "index_parallel",
      "spec" => %{
        "ioConfig" => %{
          "type" => "index_parallel",
          "inputSource" => %{
            "type" => "http",
            "uris" => ["https://druid.apache.org/data/wikipedia.json.gz"]
          },
          "inputFormat" => %{"type" => "json"}
        },
        "tuningConfig" => %{
          "type" => "index_parallel",
          "partitionsSpec" => %{"type" => "dynamic"}
        },
        # Keep one row per edit: the app shows individual edits and counts
        # them with COUNT(*).
        "dataSchema" => Spec.data_schema(Edit, segment_granularity: "DAY", rollup: false)
      }
    }
  end

  defp wait(what, check, waited \\ 0) do
    if waited > @timeout_ms, do: Mix.raise("Timed out waiting for #{what}")

    case check.() do
      :done ->
        Mix.shell().info("Done waiting for #{what}")

      {:done, count} ->
        Mix.shell().info("wiki_edits is ready with #{count} rows")

      :wait ->
        Process.sleep(@poll_ms)
        wait(what, check, waited + @poll_ms)
    end
  end
end
