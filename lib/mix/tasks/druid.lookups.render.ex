defmodule Mix.Tasks.Druid.Lookups.Render do
  @shortdoc "Renders Druid lookup templates"

  @moduledoc """
  Renders the lookup templates for a Druid repo and prints them, or writes
  them to a directory. Nothing is sent to Druid.

      mix druid.lookups.render
      mix druid.lookups.render --only countries
      mix druid.lookups.render --out tmp/lookups

  Config is loaded the same way as when the app starts, including
  `config/runtime.exs`, so environment variables apply. See `Druid.Lookups`
  for the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Render only these templates (comma-separated, or repeated).
    * `--out` - Write each lookup to `<out>/<name>.json` instead of printing.
  """

  use Mix.Task

  @switches [repo: :keep, only: :keep, out: :string]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)

    lookups =
      try do
        Druid.Lookups.render(repo, Mix.Druid.only(opts))
      rescue
        error in Druid.Lookups.Error -> Mix.raise(Exception.message(error))
      end

    Mix.Druid.print_rendered(
      lookups,
      opts[:out],
      &"#{&1.name} (lookup #{&1.tier}/#{&1.lookup})",
      & &1.factory
    )
  end
end
