defmodule Mix.Tasks.Druid.Lookups.Sync do
  @shortdoc "Submits Druid lookups"

  @moduledoc """
  Renders the lookup templates for a Druid repo and submits the lookups that
  differ from Druid's, with a new version.

      mix druid.lookups.sync --dry-run
      mix druid.lookups.sync
      mix druid.lookups.sync --only countries
      mix druid.lookups.sync --prune
      mix druid.lookups.sync --wait --timeout 300

  In a release, call `Druid.Lookups.sync/2` instead. See `Druid.Lookups` for
  the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Submit only these templates (comma-separated, or repeated).
    * `--dry-run` - Show which lookups would change without submitting them.
    * `--prune` - Delete lookups that have no template.
    * `--wait` - Wait until every synced lookup is loaded on the nodes of its
      tier. A lookup that isn't loaded in time is reported as an error.
    * `--timeout` - With `--wait`, give up after this many seconds. Defaults
      to waiting as long as it takes.

  Exits with a non-zero status if any request fails.
  """

  use Mix.Task

  @switches [
    repo: :keep,
    only: :keep,
    dry_run: :boolean,
    prune: :boolean,
    wait: :boolean,
    timeout: :integer
  ]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)

    sync_opts =
      Mix.Druid.only(opts) ++
        Keyword.take(opts, [:dry_run, :prune, :wait]) ++
        case opts[:timeout] do
          nil -> []
          seconds -> [timeout: seconds * 1000]
        end

    results =
      try do
        Druid.Lookups.sync(repo, sync_opts)
      rescue
        error in [Druid.Lookups.Error, ArgumentError] -> Mix.raise(Exception.message(error))
      end

    Mix.Druid.report_results!(results, &label/1, "lookup request(s)")
  end

  defp label(%Druid.Lookups.Lookup{name: name, tier: tier, lookup: lookup}) do
    if name in [lookup, "#{tier}/#{lookup}"],
      do: "#{tier}/#{lookup}",
      else: "#{name} (#{tier}/#{lookup})"
  end

  defp label(name), do: name
end
