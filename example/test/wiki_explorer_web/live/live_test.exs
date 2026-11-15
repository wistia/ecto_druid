defmodule WikiExplorerWeb.LiveTest do
  # Runs against a real Druid with the sample data loaded (`mix druid.setup`).
  # Excluded by default; run with `mix test --include druid`.
  use WikiExplorerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @moduletag :druid

  test "the overview shows the day's numbers", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "24,433"
    assert has_element?(view, "#top-channels", "#en.wikipedia")
    assert has_element?(view, "#top-channels", "English")
  end

  test "the overview filters out robots", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form", filters: %{robots: "false"})
      |> render_change()

    assert_patch(view, ~p"/?robots=false")
    assert html =~ "14,569"
  end

  test "searches pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/pages?q=wimbledon")

    assert has_element?(view, "#pages", "2016 Wimbledon Championships")
  end

  test "shows a page's edits", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/page?#{%{title: "Wikipedia:Vandalismusmeldung", channel: "#de.wikipedia"}}")

    assert has_element?(view, "#editors tr")
    assert has_element?(view, "#recent tr")
  end

  test "shows Druid's system tables", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/druid")

    assert has_element?(view, "#columns", "__time")
    assert has_element?(view, "#segments", "24,433")
    assert has_element?(view, "#languages", "English")
  end
end
