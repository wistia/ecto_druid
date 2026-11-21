defmodule InsertAllIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid

  import Ecto.Query
  alias Ecto.Adapters.Druid.IntegrationRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_insert_all_test"
  @copy "ecto_druid_insert_all_copy_test"
  @extern "ecto_druid_insert_all_extern_test"

  # SQL-based ingestion runs as tasks, which take a while in the test cluster
  @moduletag timeout: 600_000

  defmodule Event do
    use Ecto.Schema
    @primary_key false
    schema "ecto_druid_insert_all_test" do
      field :time, :utc_datetime, source: :__time
      field :channel, :string
      field :added, :integer
    end
  end

  setup do
    on_exit(fn ->
      for data_source <- [@data_source, @copy, @extern] do
        Druid.Client.DataSource.mark_unused(data_source) |> Druid.Client.request(@druid)
      end
    end)
  end

  defp channels(source) do
    # Druid only orders scans by __time
    IntegrationRepo.all(from e in source, select: {e.__time, e.channel, e.added})
    |> Enum.sort()
  end

  test "inserts rows, replaces an interval and copies with a query" do
    rows = [
      %{time: ~U[2026-01-01 00:00:00Z], channel: "#en", added: 1},
      %{time: ~U[2026-01-01 01:00:00Z], channel: nil, added: 2},
      %{time: ~U[2026-01-02 00:00:00Z], channel: "#fr", added: 3}
    ]

    assert {3, nil} =
             IntegrationRepo.insert_all(Event, rows,
               partitioned_by: :day,
               clustered_by: [:channel],
               wait_for_segments: true
             )

    assert channels(@data_source) == [
             {"2026-01-01T00:00:00.000Z", "#en", 1},
             {"2026-01-01T01:00:00.000Z", nil, 2},
             {"2026-01-02T00:00:00.000Z", "#fr", 3}
           ]

    # Replacing Jan 1 drops both of its rows and leaves Jan 2
    assert {1, nil} =
             IntegrationRepo.insert_all(
               Event,
               [%{time: ~U[2026-01-01 12:00:00Z], channel: "#de", added: 4}],
               partitioned_by: :day,
               overwrite: Ecto.Druid.Interval.new(~D[2026-01-01], ~D[2026-01-02]),
               wait_for_segments: true
             )

    assert channels(@data_source) == [
             {"2026-01-01T12:00:00.000Z", "#de", 4},
             {"2026-01-02T00:00:00.000Z", "#fr", 3}
           ]

    query =
      from e in @data_source,
        where: e.added > ^3,
        select: %{__time: e.__time, channel: e.channel, added: e.added * 10}

    assert {1, nil} =
             IntegrationRepo.insert_all(@copy, query,
               partitioned_by: :all,
               overwrite: :all,
               wait_for_segments: true
             )

    assert channels(@copy) == [{"2026-01-01T12:00:00.000Z", "#de", 40}]
  end

  test "inserts external data with extern/2 and extend/2" do
    import Ecto.Druid.Query.Table, only: [table: 1, extern: 2, extend: 2]
    import Ecto.Druid.Query.DateTime, only: [time_parse: 1]

    input =
      Jason.encode!(%{
        type: "inline",
        data: "2026-01-01T00:00:00Z,#en,1,a|b\n2026-01-02T00:00:00Z,#fr,2,c"
      })

    format =
      Jason.encode!(%{type: "csv", columns: ~w(ts channel added tags), listDelimiter: "|"})

    query =
      from e in extend(table(extern(^input, ^format)),
             ts: :string,
             channel: :string,
             added: :long,
             tags: {:array, :string}
           ),
           select: %{
             __time: time_parse(e.ts),
             channel: e.channel,
             added: e.added,
             tags: e.tags
           }

    assert {2, nil} =
             IntegrationRepo.insert_all(@extern, query,
               partitioned_by: :day,
               wait_for_segments: true
             )

    rows = IntegrationRepo.all(from e in @extern, select: {e.channel, e.added, e.tags})

    assert Enum.sort(rows) == [{"#en", 1, ["a", "b"]}, {"#fr", 2, ["c"]}]
  end
end
