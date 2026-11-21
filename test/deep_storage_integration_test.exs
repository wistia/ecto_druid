defmodule DeepStorageIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid

  import Ecto.Query

  alias Ecto.Adapters.Druid.IntegrationRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_deep_storage_test"

  # Each statement runs as a task, which takes several seconds even on an
  # idle cluster
  @moduletag timeout: :timer.minutes(5)
  @deep_storage [timeout: :timer.minutes(2), poll_interval: 500]

  # One day is loaded onto a Historical and the rest stay in deep storage
  # only. The Broker plans the query from the loaded day's schema, so a data
  # source needs at least one loaded segment to be queried at all.
  @rules [
    %{
      "type" => "loadByInterval",
      "interval" => "2026-01-02/2026-01-03",
      "tieredReplicants" => %{"_default_tier" => 1}
    },
    %{"type" => "loadForever", "tieredReplicants" => %{}, "useDefaultTierForNull" => false}
  ]

  @rows """
  ts,page,views
  2026-01-01T00:00:00Z,a,1
  2026-01-01T01:00:00Z,b,2
  2026-01-02T00:00:00Z,a,3
  """

  setup_all do
    Druid.Client.Retention.set(@data_source, @rules) |> Druid.Client.request!(@druid)
    ingest!()

    # The Broker reports the data source as not found until the Coordinator
    # loads the hot day
    wait_until(&loaded?/0, 120)
    :ok
  end

  test "the Broker reads only the loaded day" do
    assert IntegrationRepo.all(totals()) == [%{page: "a", views: 3}]
  end

  test "deep storage reads every day" do
    assert IntegrationRepo.all(totals(), deep_storage: @deep_storage) ==
             [%{page: "a", views: 4}, %{page: "b", views: 2}]
  end

  test "deep storage queries take parameters" do
    query = from(d in @data_source, where: d.page == ^"b", select: d.views)
    assert IntegrationRepo.all(query, deep_storage: @deep_storage) == [2]
  end

  test "streams deep storage results" do
    assert totals() |> IntegrationRepo.stream(deep_storage: @deep_storage) |> Enum.to_list() ==
             [%{page: "a", views: 4}, %{page: "b", views: 2}]
  end

  test "streams Broker results" do
    assert totals() |> IntegrationRepo.stream() |> Enum.to_list() == [%{page: "a", views: 3}]
  end

  defp totals do
    from(d in @data_source,
      group_by: d.page,
      order_by: d.page,
      select: %{page: d.page, views: sum(d.views)}
    )
  end

  # REPLACE keeps reruns from adding the rows twice
  defp ingest! do
    input = Jason.encode!(%{type: "inline", data: @rows})
    format = Jason.encode!(%{type: "csv", findColumnsFromHeader: true})

    columns =
      Jason.encode!([
        %{name: "ts", type: "string"},
        %{name: "page", type: "string"},
        %{name: "views", type: "long"}
      ])

    sql = """
    REPLACE INTO "#{@data_source}" OVERWRITE ALL
    SELECT TIME_PARSE("ts") AS __time, "page", "views"
    FROM TABLE(EXTERN(?, ?, ?))
    PARTITIONED BY DAY
    """

    params = Enum.map([input, format, columns], &%{type: "VARCHAR", value: &1})

    %{"taskId" => task_id} =
      Druid.Client.SQL.insert(sql, params) |> Druid.Client.request!(@druid)

    wait_until(
      fn ->
        %{"status" => %{"status" => status}} =
          Druid.Client.Task.status(task_id) |> Druid.Client.request!(@druid)

        if status == "FAILED", do: flunk("ingestion task #{task_id} failed")
        status == "SUCCESS"
      end,
      120
    )
  end

  defp loaded? do
    IntegrationRepo.all(totals()) != []
  rescue
    Druid.Client.RequestError -> false
  end

  defp wait_until(fun, seconds) do
    cond do
      fun.() -> :ok
      seconds <= 0 -> flunk("timed out waiting for #{@data_source}")
      true -> Process.sleep(1_000) && wait_until(fun, seconds - 1)
    end
  end
end
