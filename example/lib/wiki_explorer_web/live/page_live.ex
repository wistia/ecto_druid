defmodule WikiExplorerWeb.PageLive do
  @moduledoc """
  One page's edits. The same query functions as the overview, filtered to a
  page and channel. Titles can hold slashes, so they go in the query string.
  """
  use WikiExplorerWeb, :live_view

  alias WikiExplorer.Wiki
  alias WikiExplorerWeb.DruidErrors

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, summary: nil, hourly: [], editors: [], recent: [])}
  end

  @impl true
  def handle_params(%{"title" => title} = params, _uri, socket) do
    filters = %{page: title, channel: params["channel"]}

    socket =
      socket
      |> assign(page_title: title, title: title, channel: params["channel"])
      |> DruidErrors.load(fn ->
        %{
          summary: Wiki.summary(filters),
          hourly: Wiki.edits_by_hour(filters),
          editors: Wiki.top_editors(filters),
          recent: Wiki.recent_edits(filters)
        }
      end)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pages")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@title}
        <:subtitle :if={@channel}>{@channel}</:subtitle>
        <:actions>
          <.button navigate={~p"/pages"}>Back to pages</.button>
        </:actions>
      </.header>

      <div
        :if={@summary}
        class="stats grid w-full grid-flow-row grid-cols-2 bg-base-200 lg:grid-cols-4"
      >
        <.stat title="Edits" value={@summary.edits} />
        <.stat title="Editors" value={@summary.editors} />
        <.stat title="Characters added" value={@summary.added} />
        <.stat title="Characters deleted" value={@summary.deleted} />
      </div>

      <section :if={@hourly != []} class="card bg-base-200 p-6">
        <h2 class="mb-4 font-semibold">Edits per hour (UTC)</h2>
        <.hourly_chart rows={@hourly} />
      </section>

      <div class="grid gap-8 lg:grid-cols-2">
        <section>
          <h2 class="mb-2 font-semibold">Editors</h2>
          <.table id="editors" rows={@editors}>
            <:col :let={row} label="Editor">
              {row.user}
              <span :if={row.robot} class="badge badge-sm badge-neutral ml-1">robot</span>
            </:col>
            <:col :let={row} label="Edits">{format_number(row.edits)}</:col>
            <:col :let={row} label="Added">{format_number(row.added)}</:col>
            <:col :let={row} label="Deleted">{format_number(row.deleted)}</:col>
          </.table>
        </section>

        <section>
          <h2 class="mb-2 font-semibold">Recent edits</h2>
          <.table id="recent" rows={@recent}>
            <:col :let={row} label="Time">{Calendar.strftime(row.time, "%H:%M:%S")}</:col>
            <:col :let={row} label="Editor">{row.user}</:col>
            <:col :let={row} label="Change">{format_number(row.delta)}</:col>
            <:col :let={row} label="Comment">
              <span class="line-clamp-2 text-sm">{row.comment}</span>
            </:col>
          </.table>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
