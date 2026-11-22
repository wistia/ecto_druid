defmodule FixturesIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid
  @moduletag timeout: 600_000

  import Ecto.Query
  alias Ecto.Adapters.Druid.{IntegrationRepo, PageViews}

  @data_source "ecto_druid_fixtures_test"
  @named "ecto_druid_fixtures_named_test"
  @dropped "ecto_druid_fixtures_drop_test"
  @router [host: "localhost", port: 9888]

  setup do
    on_exit(fn ->
      Ecto.Druid.Fixtures.drop!(IntegrationRepo, [@data_source, @named, @dropped])
    end)
  end

  # 2016-06-27T01:00:00Z, and an hour, a day and a week later
  @t 1_466_989_200_000

  defp page_views do
    # Druid only orders scans by __time
    IntegrationRepo.all(
      from p in {@data_source, PageViews},
        group_by: [p.country, p.visitor_key],
        select: {p.country, p.visitor_key, sum(p.views)}
    )
    |> Enum.sort()
  end

  test "loads fixtures, and replaces them on the next load" do
    rows = [
      %{"ts" => @t, "country" => "US", "user_key" => "a", "session_id" => "s1"},
      %{"ts" => @t, "country" => "US", "user_key" => "a", "session_id" => "s2"},
      %{"ts" => @t + 86_400_000, "country" => "CA", "user_key" => "b", "session_id" => "s3"}
    ]

    named = [%{"timestamp" => "2016-06-27T01:00:00Z", "page" => "Main"}]

    data_schema = %{
      timestampSpec: %{column: "timestamp", format: "iso"},
      dimensionsSpec: %{dimensions: ["page"]}
    }

    assert :ok =
             Ecto.Druid.Fixtures.load!(IntegrationRepo, [
               {PageViews, rows, data_source: @data_source},
               {@named, named, data_schema: data_schema}
             ])

    # With user_key read into visitor_key, and rows counted
    assert page_views() == [{"CA", "b", 1}, {"US", "a", 2}]
    assert IntegrationRepo.all(from e in @named, select: e.page) == ["Main"]

    # A later day, so nothing overwrites the first load's segments but the
    # drop
    rows = [%{"ts" => @t + 7 * 86_400_000, "country" => "FR", "user_key" => "c"}]

    assert :ok =
             Ecto.Druid.Fixtures.load!(IntegrationRepo, [
               {PageViews, rows, data_source: @data_source}
             ])

    assert page_views() == [{"FR", "c", 1}]
  end

  defp segments(state) do
    path = if state == :used, do: "segments", else: "unusedSegments"
    url = "/druid/coordinator/v1/metadata/datasources/#{@dropped}/#{path}"

    case Druid.Client.request(Req.new(url: url), @router) do
      {:ok, segments} -> segments
      {:error, %Druid.Client.RequestError{status: 404}} -> []
    end
  end

  test "drop! deletes every segment, and the Broker stops listing the data source" do
    # PARTITIONED BY ALL makes one segment over Druid's whole timeline
    sql = """
    INSERT INTO "#{@dropped}"
    SELECT TIME_PARSE('2026-01-01T00:00:00Z') AS __time, 'a' AS page
    PARTITIONED BY ALL
    """

    %{"taskId" => task_id} = Druid.Client.SQL.insert(sql) |> Druid.Client.request!(@router)
    {:ok, _} = Druid.Tasks.await(IntegrationRepo, task_id, wait_for_segments: true)
    assert IntegrationRepo.all(from e in @dropped, select: e.page) == ["a"]

    assert :ok = Ecto.Druid.Fixtures.drop!(IntegrationRepo, @dropped)

    assert segments(:used) == []
    assert segments(:unused) == []

    assert_raise Druid.Client.RequestError, ~r/not found/i, fn ->
      IntegrationRepo.all(from e in @dropped, select: e.page)
    end

    # A data source that's gone is fine
    assert :ok = Ecto.Druid.Fixtures.drop!(IntegrationRepo, @dropped)
  end
end
