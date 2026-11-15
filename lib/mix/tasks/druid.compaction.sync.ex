defmodule Mix.Tasks.Druid.Compaction.Sync do
  @shortdoc "Submits Druid compaction configs"

  @moduledoc """
  Renders the compaction config templates for a Druid repo and submits the
  configs that differ from Druid's.

      mix druid.compaction.sync --dry-run
      mix druid.compaction.sync
      mix druid.compaction.sync --only page_views_hourly
      mix druid.compaction.sync --prune

  In a release, call `Druid.Compaction.sync/2` instead. See
  `Druid.Compaction` for the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Submit only these templates (comma-separated, or repeated).
    * `--dry-run` - Show which configs would change without submitting them.
    * `--force` - Submit every config, even ones that look unchanged. Use it
      after removing a setting from a template.
    * `--prune` - Delete the compaction configs of data sources that have no
      template.

  Exits with a non-zero status if any request fails.
  """

  use Mix.Task

  @switches [
    repo: :keep,
    only: :keep,
    dry_run: :boolean,
    force: :boolean,
    prune: :boolean
  ]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)
    sync_opts = Mix.Druid.only(opts) ++ Keyword.take(opts, [:dry_run, :force, :prune])

    results =
      try do
        Druid.Compaction.sync(repo, sync_opts)
      rescue
        error in [Druid.Compaction.Error, ArgumentError] -> Mix.raise(Exception.message(error))
      end

    Mix.Druid.report_results!(results, &label/1, "compaction request(s)")
  end

  defp label(%Druid.Compaction.Config{name: name, data_source: name}), do: name
  defp label(%Druid.Compaction.Config{name: name, data_source: ds}), do: "#{name} (#{ds})"
  defp label(data_source), do: data_source
end
