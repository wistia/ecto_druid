defmodule CompactionIntegrationTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_compaction_test"

  setup do
    on_exit(fn ->
      Druid.Client.Compaction.delete(@data_source) |> Druid.Client.request(@druid)
    end)
  end

  defp get! do
    Druid.Client.Compaction.get(@data_source) |> Druid.Client.request!(@druid)
  end

  test "creates, leaves unchanged, and updates a compaction config" do
    sync = &Druid.Compaction.sync(TestRepo, [only: [@data_source]] ++ &1)

    assert [{:would_create, _}] = sync.(dry_run: true)
    assert [{:created, _}] = sync.([])

    # Druid expands the config (string dimensions, sketch defaults, tuning
    # defaults), and it still matches the template
    stored = get!()
    assert %{"type" => "string", "name" => "country"} = hd(stored["dimensionsSpec"]["dimensions"])
    assert [{:unchanged, _}] = sync.([])

    assert [{:would_update, _}] =
             sync.(dry_run: true, specs: %{@data_source => %{target_rows: 1_000_000}})

    assert [{:updated, _}] = sync.(specs: %{@data_source => %{target_rows: 1_000_000}})
    assert get!()["tuningConfig"]["partitionsSpec"]["maxRowsPerSegment"] == 1_000_000

    # With compaction supervisors (the default), Druid 38 keeps the config
    # history but not the audit author and comment
    %{"entries" => [%{"compactionConfig" => latest} | _]} =
      Druid.Client.Compaction.history(@data_source, count: 1) |> Druid.Client.request!(@druid)

    assert latest["tuningConfig"]["partitionsSpec"]["maxRowsPerSegment"] == 1_000_000
  end
end
