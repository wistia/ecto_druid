defmodule ProjectionIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid

  import Ecto.Query
  import Ecto.Druid.Query.DateTime, only: [time_floor: 2]
  alias Ecto.Adapters.Druid.IntegrationRepo
  alias Ecto.Druid.Sys

  @data_source "ecto_druid_projection_test"

  # Batch ingestion runs as a task, which takes a while in the test cluster
  @moduletag timeout: 600_000

  defmodule Edit do
    use Ecto.Druid.Schema
    @primary_key false
    schema "ecto_druid_projection_test" do
      timestamp :time, column: "ts", format: "iso"
      dimension :channel, :string
      dimension :user, :string
      dimension :added, :integer

      projection :channel_hourly,
        granularity: :hour,
        group_by: [:channel],
        aggregate: [added: {:sum, :added}, edits: :count]
    end
  end

  setup do
    on_exit(fn -> Ecto.Druid.Fixtures.drop!(IntegrationRepo, @data_source) end)
  end

  test "ingestion specs built from a schema build its projections, which queries use" do
    rows = [
      %{ts: "2026-01-01T01:10:00Z", channel: "a", user: "u1", added: 1},
      %{ts: "2026-01-01T01:20:00Z", channel: "a", user: "u2", added: 2},
      %{ts: "2026-01-01T02:10:00Z", channel: "b", user: "u1", added: 3}
    ]

    spec = %{
      "type" => "index_parallel",
      "spec" => %{
        "ioConfig" => %{
          "type" => "index_parallel",
          "inputSource" => %{
            "type" => "inline",
            "data" => Enum.map_join(rows, "\n", &Jason.encode!/1)
          },
          "inputFormat" => %{"type" => "json"}
        },
        "tuningConfig" => %{"type" => "index_parallel"},
        "dataSchema" => Ecto.Druid.Schema.Spec.data_schema(Edit, segment_granularity: "DAY")
      }
    }

    assert {:ok, _} = Druid.Tasks.run(IntegrationRepo, spec, wait_for_segments: true)

    # The data is queryable once the task's segments are loaded, but the
    # Broker's sys.segments shows them as published, and so active, a few
    # seconds later
    active_projections = fn ->
      case IntegrationRepo.all(
             from s in Sys.Segments,
               where: s.datasource == ^@data_source and s.is_active == 1,
               select: s.projections
           ) do
        [] -> :wait
        projections -> {:done, projections}
      end
    end

    assert {:ok, [["channel_hourly"]]} =
             Druid.Poll.poll(Druid.Poll.deadline(30_000), 200, active_projections)

    # forceProjections fails a query that no projection can answer
    query =
      from e in Edit,
        group_by: [time_floor(e.time, "PT1H"), e.channel],
        order_by: [time_floor(e.time, "PT1H"), e.channel],
        select: {e.channel, sum(e.added), count()}

    assert IntegrationRepo.all(query, context: %{forceProjections: true}) ==
             [{"a", 3, 2}, {"b", 3, 1}]

    by_user = from e in Edit, group_by: e.user, select: {e.user, sum(e.added)}

    assert_raise Druid.Client.RequestError, ~r/[Ff]orce projections/, fn ->
      IntegrationRepo.all(by_user, context: %{forceProjections: true})
    end
  end
end
