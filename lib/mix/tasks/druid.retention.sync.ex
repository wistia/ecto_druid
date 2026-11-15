defmodule Mix.Tasks.Druid.Retention.Sync do
  @shortdoc "Submits Druid retention rules"

  @moduledoc """
  Renders the retention rule templates for a Druid repo and submits the rules
  that differ from Druid's.

      mix druid.retention.sync --dry-run
      mix druid.retention.sync
      mix druid.retention.sync --only page_views_hourly
      mix druid.retention.sync --prune

  In a release, call `Druid.Retention.sync/2` instead. See `Druid.Retention`
  for the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Submit only these templates (comma-separated, or repeated).
    * `--dry-run` - Show which rules would change without submitting them.
    * `--prune` - Remove the rules of data sources that have no template.

  Exits with a non-zero status if any request fails.
  """

  use Mix.Task

  @switches [repo: :keep, only: :keep, dry_run: :boolean, prune: :boolean]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)
    sync_opts = Mix.Druid.only(opts) ++ Keyword.take(opts, [:dry_run, :prune])

    results =
      try do
        Druid.Retention.sync(repo, sync_opts)
      rescue
        error in [Druid.Retention.Error, ArgumentError] -> Mix.raise(Exception.message(error))
      end

    Mix.Druid.report_results!(results, &label/1, "retention rule request(s)")
  end

  defp label(%Druid.Retention.Rules{name: name, data_source: name}), do: name
  defp label(%Druid.Retention.Rules{name: name, data_source: ds}), do: "#{name} (#{ds})"
  defp label(data_source), do: data_source
end
