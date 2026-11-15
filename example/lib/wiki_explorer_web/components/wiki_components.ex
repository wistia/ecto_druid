defmodule WikiExplorerWeb.WikiComponents do
  @moduledoc "Small display components shared by the LiveViews."
  use Phoenix.Component

  @doc "A headline number."
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :desc, :string, default: nil

  def stat(assigns) do
    ~H"""
    <div class="stat">
      <div class="stat-title">{@title}</div>
      <div class="stat-value text-2xl">{format_number(@value)}</div>
      <div :if={@desc} class="stat-desc">{@desc}</div>
    </div>
    """
  end

  @doc """
  A bar chart of edits per hour, drawn with plain divs. Robot edits are the
  solid part of each bar.
  """
  attr :rows, :list, required: true

  def hourly_chart(assigns) do
    assigns = assign(assigns, :max, assigns.rows |> Enum.map(& &1.edits) |> Enum.max(fn -> 1 end))

    ~H"""
    <div class="flex h-48 items-end gap-1" role="img" aria-label="Edits per hour">
      <div
        :for={row <- @rows}
        class="group relative flex h-full flex-1 flex-col justify-end"
        title={"#{Calendar.strftime(row.hour, "%H:00")} UTC: #{format_number(row.edits)} edits, #{format_number(row.robot_edits)} by robots"}
      >
        <div
          class="w-full rounded-t bg-primary/40 group-hover:bg-primary/60"
          style={"height: #{percent(row.edits - row.robot_edits, @max)}%"}
        />
        <div class="w-full bg-primary" style={"height: #{percent(row.robot_edits, @max)}%"} />
      </div>
    </div>
    <div class="mt-1 flex justify-between text-xs opacity-60">
      <span>00:00</span><span>06:00</span><span>12:00</span><span>18:00</span><span>23:00</span>
    </div>
    """
  end

  @doc "A horizontal bar showing `value` relative to `max`."
  attr :value, :integer, required: true
  attr :max, :integer, required: true

  def meter(assigns) do
    ~H"""
    <div class="h-2 w-full rounded bg-base-300">
      <div class="h-2 rounded bg-primary" style={"width: #{percent(@value, @max)}%"} />
    </div>
    """
  end

  def format_number(nil), do: "–"
  def format_number(n) when is_float(n), do: n |> round() |> format_number()

  def format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  def format_number(other), do: to_string(other)

  def format_bytes(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  def format_bytes(bytes) when bytes >= 1_000, do: "#{Float.round(bytes / 1_000, 1)} KB"
  def format_bytes(bytes), do: "#{bytes} B"

  defp percent(_value, max) when max in [0, nil], do: 0
  defp percent(value, max), do: Float.round(value / max * 100, 2)
end
