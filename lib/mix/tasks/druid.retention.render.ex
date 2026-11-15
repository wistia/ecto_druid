defmodule Mix.Tasks.Druid.Retention.Render do
  @shortdoc "Renders Druid retention rule templates"

  @moduledoc """
  Renders the retention rule templates for a Druid repo and prints them, or
  writes them to a directory. Nothing is sent to Druid.

      mix druid.retention.render
      mix druid.retention.render --only page_views_hourly
      mix druid.retention.render --out tmp/retention

  Config is loaded the same way as when the app starts, including
  `config/runtime.exs`, so environment variables apply. See `Druid.Retention`
  for the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Render only these templates (comma-separated, or repeated).
    * `--out` - Write each template's rules to `<out>/<name>.json` instead of
      printing.
  """

  use Mix.Task

  @switches [repo: :keep, only: :keep, out: :string]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)

    rules =
      try do
        Druid.Retention.render(repo, Mix.Druid.only(opts))
      rescue
        error in Druid.Retention.Error -> Mix.raise(Exception.message(error))
      end

    Mix.Druid.print_rendered(
      rules,
      opts[:out],
      &header/1,
      & &1.rules
    )
  end

  defp header(%{name: name, data_source: name}), do: "rules for #{name}"
  defp header(%{name: name, data_source: ds}), do: "#{name} (rules for #{ds})"
end
