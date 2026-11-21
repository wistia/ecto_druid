defmodule FixturesIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid
  @moduletag timeout: 600_000

  import Ecto.Query
  alias Ecto.Adapters.Druid.{IntegrationRepo, PageViews}

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_fixtures_test"
  @named "ecto_druid_fixtures_named_test"

  setup do
    on_exit(fn ->
      for data_source <- [@data_source, @named] do
        Druid.Client.DataSource.mark_unused(data_source) |> Druid.Client.request(@druid)
      end
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
end
