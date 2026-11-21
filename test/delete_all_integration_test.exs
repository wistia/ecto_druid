defmodule DeleteAllIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid

  import Ecto.Query
  alias Ecto.Adapters.Druid.IntegrationRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_delete_all_test"

  # SQL-based ingestion runs as tasks, which take a while in the test cluster
  @moduletag timeout: 600_000

  defmodule Event do
    use Ecto.Schema
    @primary_key false
    schema "ecto_druid_delete_all_test" do
      field :time, :utc_datetime, source: :__time
      field :channel, :string
      field :added, :integer
    end
  end

  setup do
    on_exit(fn ->
      Druid.Client.DataSource.mark_unused(@data_source) |> Druid.Client.request(@druid)
    end)
  end

  defp rows do
    # Druid only orders scans by __time
    IntegrationRepo.all(from e in @data_source, select: {e.__time, e.channel, e.added})
    |> Enum.sort()
  end

  test "deletes matching rows from an interval, keeping rows the condition is NULL for" do
    rows = [
      %{time: ~U[2026-01-01 00:00:00Z], channel: "#en", added: 1},
      %{time: ~U[2026-01-01 01:00:00Z], channel: nil, added: 2},
      %{time: ~U[2026-01-01 02:00:00Z], channel: "#fr", added: 3},
      %{time: ~U[2026-01-02 00:00:00Z], channel: "#en", added: 4}
    ]

    assert {4, nil} =
             IntegrationRepo.insert_all(Event, rows,
               partitioned_by: :day,
               wait_for_segments: true
             )

    # Only Jan 1 is rewritten, so Jan 2's #en row stays. The NULL channel
    # isn't "#en", so its row stays too.
    assert {1, nil} =
             IntegrationRepo.delete_all(
               from(e in Event, where: e.channel == ^"#en"),
               interval: Ecto.Druid.Interval.new(~D[2026-01-01], ~D[2026-01-02]),
               partitioned_by: :day,
               wait_for_segments: true
             )

    assert rows() == [
             {"2026-01-01T01:00:00.000Z", nil, 2},
             {"2026-01-01T02:00:00.000Z", "#fr", 3},
             {"2026-01-02T00:00:00.000Z", "#en", 4}
           ]

    # Without a where clause, every row in the interval goes
    assert {1, nil} =
             IntegrationRepo.delete_all(Event,
               interval: "2026-01-02/2026-01-03",
               partitioned_by: :day,
               wait_for_segments: true
             )

    assert rows() == [
             {"2026-01-01T01:00:00.000Z", nil, 2},
             {"2026-01-01T02:00:00.000Z", "#fr", 3}
           ]
  end
end
