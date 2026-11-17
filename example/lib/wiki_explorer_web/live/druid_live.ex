defmodule WikiExplorerWeb.DruidLive do
  @moduledoc """
  A look at Druid itself: the data source's schema and segments from the
  system tables, the cluster's services, the lookup read as a table, and a
  native `topN` query.
  """
  use WikiExplorerWeb, :live_view

  alias WikiExplorer.{Cluster, Wiki}
  alias WikiExplorerWeb.DruidErrors

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Druid",
        columns: [],
        segments: [],
        servers: [],
        languages: [],
        top_n: []
      )
      |> DruidErrors.load(fn ->
        %{
          columns: Cluster.columns(),
          segments: Cluster.segments(),
          servers: Cluster.servers(),
          top_n: Wiki.top_channels_native()
        }
      end)
      # Loaded on its own so the page still works while Druid is loading the lookup
      |> DruidErrors.load(fn -> %{languages: Cluster.channel_languages()} end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Inside Druid
        <:subtitle>
          Read with the <code>Ecto.Druid.Sys</code>
          and <code>Ecto.Druid.InformationSchema</code>
          schemas, a lookup schema, and <code>native_query!/2</code>.
        </:subtitle>
      </.header>

      <div class="grid gap-8 lg:grid-cols-2">
        <section>
          <h2 class="mb-2 font-semibold">
            Columns of <code>{Cluster.data_source()}</code>
          </h2>
          <p class="mb-2 text-sm opacity-60">From <code>INFORMATION_SCHEMA.COLUMNS</code>.</p>
          <.table id="columns" rows={@columns}>
            <:col :let={col} label="Column"><code>{col.name}</code></:col>
            <:col :let={col} label="Type">{col.type}</:col>
          </.table>
        </section>

        <div class="space-y-8">
          <section>
            <h2 class="mb-2 font-semibold">Segments</h2>
            <p class="mb-2 text-sm opacity-60">From <code>sys.segments</code>.</p>
            <.table id="segments" rows={@segments}>
              <:col :let={seg} label="Interval">{seg.start} / {seg.end}</:col>
              <:col :let={seg} label="Rows">{format_number(seg.num_rows)}</:col>
              <:col :let={seg} label="Size">{format_bytes(seg.size)}</:col>
              <:col :let={seg} label="Loaded">{if seg.is_available, do: "yes", else: "no"}</:col>
            </.table>
          </section>

          <section>
            <h2 class="mb-2 font-semibold">Services</h2>
            <p class="mb-2 text-sm opacity-60">From <code>sys.servers</code>.</p>
            <.table id="servers" rows={@servers}>
              <:col :let={s} label="Type">{s.type}</:col>
              <:col :let={s} label="Server"><code>{s.server}</code></:col>
              <:col :let={s} label="Segments cached">{format_bytes(s.curr_size)}</:col>
            </.table>
          </section>

          <section>
            <h2 class="mb-2 font-semibold">Native topN query</h2>
            <p class="mb-2 text-sm opacity-60">
              <code>DruidRepo.native_query!/2</code> with <code>queryType: "topN"</code>.
            </p>
            <.table id="top-n" rows={@top_n}>
              <:col :let={row} label="Channel">{row["channel"]}</:col>
              <:col :let={row} label="Edits">{format_number(row["edits"])}</:col>
              <:col :let={row} label="Added">{format_number(row["added"])}</:col>
            </.table>
          </section>

          <section>
            <h2 class="mb-2 font-semibold">The <code>channel_languages</code> lookup</h2>
            <p class="mb-2 text-sm opacity-60">
              Read with <code>Repo.all(ChannelLanguages)</code>.
              Defined in <code>priv/druid/lookups</code>, synced by <code>mix druid.lookups.sync</code>.
            </p>
            <.table id="languages" rows={@languages}>
              <:col :let={l} label="Channel">{l.channel}</:col>
              <:col :let={l} label="Language">{l.language}</:col>
            </.table>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
