defmodule WikiExplorer.WikiTest do
  # Checks the SQL the queries generate. Doesn't need Druid.
  use ExUnit.Case, async: true

  alias WikiExplorer.Wiki

  test "the base query filters on time, channel and robots" do
    {sql, params} =
      Wiki.to_sql(Wiki.edits(%{channel: "#en.wikipedia", robots: false, page: nil}))

    assert sql =~ ~s|FROM "wiki_edits"|
    assert sql =~ ~s|TIME_IN_INTERVAL(w0."__time", ?)|
    assert sql =~ ~s|w0."channel" = ?|
    assert sql =~ ~s|w0."isRobot" = 'false'|
    refute sql =~ ~s|"page" =|
    assert params == ["2016-06-27/P1D", "#en.wikipedia"]
  end

  test "the summary uses sketches for distinct counts" do
    {sql, _params} = Wiki.to_sql(Wiki.summary_query(%{}))

    assert sql =~ ~s|APPROX_COUNT_DISTINCT_DS_HLL(w0."user")|
    assert sql =~ ~s|APPROX_COUNT_DISTINCT_DS_THETA(w0."page")|
    assert sql =~ ~s|APPROX_QUANTILE_DS(w0."delta", 0.5)|
  end
end
