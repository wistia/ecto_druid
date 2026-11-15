defmodule Mix.Tasks.Druid.Compaction.Render do
  @shortdoc "Renders Druid compaction config templates"

  @moduledoc """
  Renders the compaction config templates for a Druid repo and prints them,
  or writes them to a directory. Nothing is sent to Druid.

      mix druid.compaction.render
      mix druid.compaction.render --only page_views_hourly
      mix druid.compaction.render --out tmp/compaction

  Config is loaded the same way as when the app starts, including
  `config/runtime.exs`, so environment variables apply. See `Druid.Compaction`
  for the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Render only these templates (comma-separated, or repeated).
    * `--out` - Write each config to `<out>/<name>.json` instead of printing.
  """

  use Mix.Task

  @switches [repo: :keep, only: :keep, out: :string]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)

    configs =
      try do
        Druid.Compaction.render(repo, Mix.Druid.only(opts))
      rescue
        error in Druid.Compaction.Error -> Mix.raise(Exception.message(error))
      end

    Mix.Druid.print_rendered(configs, opts[:out], &header/1, & &1.config)
  end

  defp header(%{name: name, data_source: name}), do: "compaction for #{name}"
  defp header(%{name: name, data_source: ds}), do: "#{name} (compaction for #{ds})"
end
