defmodule WikiExplorerWeb.DruidErrors do
  @moduledoc """
  Runs Druid queries for a LiveView and turns failures into a flash message,
  so a missing data source or a stopped Druid shows how to fix it instead of
  crashing the page.
  """
  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 2]

  require Logger

  def load(socket, fun) do
    assign(socket, fun.())
  rescue
    error ->
      Logger.error(Exception.format(:error, error, __STACKTRACE__))

      put_flash(
        socket,
        :error,
        "Druid query failed: #{error |> Exception.message() |> String.slice(0, 300)}. " <>
          "Is Druid running, and has `mix druid.setup` loaded the sample data?"
      )
  end
end
