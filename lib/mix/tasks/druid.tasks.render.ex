defmodule Mix.Tasks.Druid.Tasks.Render do
  @shortdoc "Renders Druid task spec templates"

  @moduledoc """
  Renders the task spec templates for a Druid repo and prints them, or writes
  them to a directory. Nothing is sent to Druid.

      mix druid.tasks.render
      mix druid.tasks.render --only reindex_page_views --assign interval=2026-11-01/P1D
      mix druid.tasks.render --out tmp/tasks

  Config is loaded the same way as when the app starts, including
  `config/runtime.exs`, so environment variables apply. See `Druid.Tasks` for
  the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Render only these templates (comma-separated, or repeated).
    * `--assign` - Set an assign for this run, as `key=value` (repeatable).
      Values are strings, so render them with `json @key`.
    * `--out` - Write each spec to `<out>/<name>.json` instead of printing.
  """

  use Mix.Task

  @switches [repo: :keep, only: :keep, assign: :keep, out: :string]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)

    specs =
      try do
        Druid.Tasks.render(repo, Mix.Druid.only(opts) ++ Mix.Druid.assigns(opts))
      rescue
        error in Druid.Tasks.Error -> Mix.raise(Exception.message(error))
      end

    Mix.Druid.print_rendered(specs, opts[:out], &header/1, & &1.spec)
  end

  defp header(%{name: name, data_source: nil}), do: name
  defp header(%{name: name, data_source: name}), do: "#{name} (task)"
  defp header(%{name: name, data_source: ds}), do: "#{name} (task for #{ds})"
end
