defmodule RetentionLookupsIntegrationTest do
  use ExUnit.Case

  @moduletag :druid

  alias Ecto.Adapters.Druid.TestRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_retention_test"
  @lookup "ecto_druid_lookup_test"

  setup do
    on_exit(fn ->
      Druid.Client.Retention.set(@data_source, []) |> Druid.Client.request(@druid)
      Druid.Client.Lookup.delete("__default", @lookup) |> Druid.Client.request(@druid)
    end)
  end

  test "creates, leaves unchanged, and updates retention rules" do
    sync = &Druid.Retention.sync(TestRepo, [only: [@data_source]] ++ &1)

    assert [{:would_create, _}] = sync.(dry_run: true)
    assert [{:created, _}] = sync.([])

    # Druid stores the rules with its defaults filled in and the interval
    # normalized, and they still compare equal
    stored = Druid.Client.Retention.get(@data_source) |> Druid.Client.request!(@druid)
    assert Enum.at(stored, 1)["interval"] == "2020-01-01T00:00:00.000Z/2021-01-01T00:00:00.000Z"
    assert [{:unchanged, _}] = sync.([])

    assert [{:would_update, _}] = sync.(dry_run: true, specs: %{@data_source => %{keep: "P1Y"}})
    assert [{:updated, _}] = sync.(specs: %{@data_source => %{keep: "P1Y"}})

    assert [%{"period" => "P1Y"} | _] =
             Druid.Client.Retention.get(@data_source) |> Druid.Client.request!(@druid)

    [%{"auditInfo" => audit} | _] =
      Druid.Client.Retention.history(@data_source, count: 1) |> Druid.Client.request!(@druid)

    assert audit["author"] == "ecto_druid"
    assert audit["comment"] == "Synced from retention template #{@data_source}"
  end

  test "refuses rules for a tier with no Historicals" do
    assert [{:error, _, error}] =
             Druid.Retention.sync(TestRepo,
               only: [@data_source],
               specs: %{@data_source => %{tier: "missing"}}
             )

    assert Exception.message(error) =~ "unknown tiers"
    assert Druid.Client.Retention.get(@data_source) |> Druid.Client.request!(@druid) == []
  end

  test "creates, leaves unchanged, and updates a lookup" do
    sync = &Druid.Lookups.sync(TestRepo, [only: [@lookup]] ++ &1)

    assert [{:created, _}] = sync.([])
    assert [{:unchanged, _}] = sync.([])

    %{"version" => first} = get_lookup()

    assert [{:updated, _}] = sync.(assigns: %{countries: %{"MX" => "Mexico"}})

    assert %{"version" => second, "lookupExtractorFactory" => factory} = get_lookup()
    assert second > first
    assert factory == %{"type" => "map", "map" => %{"MX" => "Mexico"}}
  end

  defp get_lookup do
    Druid.Client.Lookup.get("__default", @lookup) |> Druid.Client.request!(@druid)
  end
end
