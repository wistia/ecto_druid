defmodule WikiExplorerWeb.PageSearchLive do
  @moduledoc "Finds pages by title with a case-insensitive substring search."
  use WikiExplorerWeb, :live_view

  alias WikiExplorer.Wiki
  alias WikiExplorerWeb.DruidErrors

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Pages", results: [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    term = params |> Map.get("q", "") |> String.trim()

    socket =
      socket
      |> assign(term: term, form: to_form(%{"q" => term}))
      |> DruidErrors.load(fn ->
        %{results: if(term == "", do: Wiki.top_pages(%{}, 25), else: Wiki.search_pages(term))}
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => term}, socket) do
    {:noreply, push_patch(socket, to: ~p"/pages?#{%{q: term}}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Pages
        <:subtitle>
          Search page titles. The search runs <code>ICONTAINS_STRING</code> in Druid as you type.
        </:subtitle>
      </.header>

      <.form for={@form} phx-change="search" phx-submit="search" class="max-w-md">
        <.input
          field={@form[:q]}
          type="search"
          placeholder="Try “wimbledon” or “euro 2016”"
          phx-debounce="300"
          autocomplete="off"
        />
      </.form>

      <p class="text-sm opacity-60">
        {if @term == "", do: "The most edited pages:", else: "Pages matching “#{@term}”:"}
      </p>

      <.table id="pages" rows={@results}>
        <:col :let={row} label="Page">
          <.link navigate={~p"/page?#{%{title: row.page, channel: row.channel}}"} class="link">
            {row.page}
          </.link>
        </:col>
        <:col :let={row} label="Channel">{row.channel}</:col>
        <:col :let={row} label="Edits">{format_number(row.edits)}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
