defmodule WikiExplorerWeb.OverviewLive do
  @moduledoc """
  A day of Wikipedia edits: headline numbers, edits per hour, and the top
  channels, pages, countries and editors. The filters live in the URL, so
  every view can be linked to.
  """
  use WikiExplorerWeb, :live_view

  alias WikiExplorer.Wiki
  alias WikiExplorerWeb.DruidErrors

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Overview",
        channels: [],
        summary: nil,
        hourly: [],
        top_channels: [],
        top_pages: [],
        top_countries: [],
        top_editors: [],
        sql: nil
      )
      |> DruidErrors.load(fn -> %{channels: Wiki.channels()} end)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{channel: params["channel"], robots: params["robots"] != "false"}

    socket =
      socket
      |> assign(filters: filters, form: to_form(form_params(filters), as: :filters))
      |> DruidErrors.load(fn ->
        %{
          summary: Wiki.summary(filters),
          hourly: Wiki.edits_by_hour(filters),
          top_channels: Wiki.top_channels(filters),
          top_pages: Wiki.top_pages(filters),
          top_countries: Wiki.top_countries(filters),
          top_editors: Wiki.top_editors(filters),
          sql: Wiki.to_sql(Wiki.summary_query(filters))
        }
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = %{channel: params["channel"], robots: params["robots"] != "false"}
    {:noreply, push_patch(socket, to: overview_path(filters))}
  end

  defp overview_path(filters) do
    query =
      Enum.reject(
        [channel: filters.channel, robots: if(!filters.robots, do: "false")],
        fn {_k, v} -> v in [nil, ""] end
      )

    ~p"/?#{query}"
  end

  defp form_params(filters) do
    %{"channel" => filters.channel, "robots" => to_string(filters.robots)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Wikipedia edits on June 27, 2016
        <:subtitle>
          Every query on this page is an Ecto query against Druid's <code>wiki_edits</code>
          data source.
        </:subtitle>
      </.header>

      <.form for={@form} phx-change="filter" class="flex flex-wrap items-end gap-6">
        <div class="w-64">
          <.input
            field={@form[:channel]}
            type="select"
            label="Channel"
            prompt="All channels"
            options={@channels}
          />
        </div>
        <div>
          <.input field={@form[:robots]} type="checkbox" label="Include robots" />
        </div>
      </.form>

      <div
        :if={@summary}
        class="stats grid w-full grid-flow-row grid-cols-2 bg-base-200 lg:grid-cols-3"
      >
        <.stat title="Edits" value={@summary.edits} />
        <.stat title="Editors" value={@summary.editors} desc="approximate (HLL sketch)" />
        <.stat title="Pages" value={@summary.pages} desc="approximate (Theta sketch)" />
        <.stat title="Characters added" value={@summary.added} />
        <.stat title="Characters deleted" value={@summary.deleted} />
        <.stat
          title="Median change"
          value={@summary.median_delta}
          desc={"p90: #{format_number(@summary.p90_delta)} (quantiles sketch)"}
        />
      </div>

      <section :if={@hourly != []} class="card bg-base-200 p-6">
        <h2 class="mb-4 font-semibold">
          Edits per hour (UTC) <span class="text-sm font-normal opacity-60">solid: robot edits</span>
        </h2>
        <.hourly_chart rows={@hourly} />
      </section>

      <div class="grid gap-8 lg:grid-cols-2">
        <section>
          <h2 class="mb-2 font-semibold">Top channels</h2>
          <p class="mb-2 text-sm opacity-60">
            Language names come from the <code>channel_languages</code> lookup.
          </p>
          <.table id="top-channels" rows={@top_channels}>
            <:col :let={row} label="Channel">
              <.link patch={overview_path(%{@filters | channel: row.channel})} class="link">{row.channel}</.link>
            </:col>
            <:col :let={row} label="Language">{row.language}</:col>
            <:col :let={row} label="Edits">{format_number(row.edits)}</:col>
            <:col :let={row} label="Editors">{format_number(row.editors)}</:col>
          </.table>
        </section>

        <section>
          <h2 class="mb-2 font-semibold">Top pages</h2>
          <p class="mb-2 text-sm opacity-60">Net change is characters added minus deleted.</p>
          <.table id="top-pages" rows={@top_pages}>
            <:col :let={row} label="Page">
              <.link navigate={~p"/page?#{%{title: row.page, channel: row.channel}}"} class="link">
                {row.page}
              </.link>
            </:col>
            <:col :let={row} label="Edits">{format_number(row.edits)}</:col>
            <:col :let={row} label="Net change">{format_number(row.delta)}</:col>
          </.table>
        </section>

        <section>
          <h2 class="mb-2 font-semibold">Top editors</h2>
          <.table id="top-editors" rows={@top_editors}>
            <:col :let={row} label="Editor">
              {row.user}
              <span :if={row.robot} class="badge badge-sm badge-neutral ml-1">robot</span>
            </:col>
            <:col :let={row} label="Edits">{format_number(row.edits)}</:col>
            <:col :let={row} label="Added">{format_number(row.added)}</:col>
          </.table>
        </section>

        <section>
          <h2 class="mb-2 font-semibold">Anonymous edits by country</h2>
          <div class="space-y-2">
            <div
              :for={row <- @top_countries}
              class="grid grid-cols-[10rem_1fr_4rem] items-center gap-3"
            >
              <span class="truncate text-sm">{row.country}</span>
              <.meter value={row.edits} max={hd(@top_countries).edits} />
              <span class="text-right text-sm">{format_number(row.edits)}</span>
            </div>
          </div>
        </section>
      </div>

      <details :if={@sql} class="collapse collapse-arrow bg-base-200">
        <summary class="collapse-title font-semibold">The SQL behind the headline numbers</summary>
        <div class="collapse-content">
          <pre class="overflow-x-auto text-sm whitespace-pre-wrap"><code>{elem(@sql, 0)}</code></pre>
          <p class="mt-2 text-sm opacity-60">Parameters: {inspect(elem(@sql, 1))}</p>
        </div>
      </details>
    </Layouts.app>
    """
  end
end
