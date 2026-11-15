defmodule Mix.Tasks.Druid.Supervisors.Sync do
  @shortdoc "Submits Druid supervisor specs"

  @moduledoc """
  Renders the supervisor spec templates for a Druid repo and submits them to
  Druid. Druid only restarts a supervisor when its spec changed.

      mix druid.supervisors.sync --dry-run
      mix druid.supervisors.sync
      mix druid.supervisors.sync --only page_views_hourly
      mix druid.supervisors.sync --prune

  In a release, call `Druid.Supervisors.sync/2` instead. See
  `Druid.Supervisors` for the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Submit only these specs (comma-separated, or repeated).
    * `--dry-run` - Show which supervisors would be created or updated
      without submitting anything.
    * `--prune` - Terminate running supervisors that have no template.
    * `--restart` - Restart every submitted supervisor, even unchanged ones.

  Exits with a non-zero status if any request fails.
  """

  use Mix.Task

  @switches [repo: :keep, only: :keep, dry_run: :boolean, prune: :boolean, restart: :boolean]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)

    sync_opts =
      Mix.Druid.only(opts) ++ Keyword.take(opts, [:dry_run, :prune, :restart])

    results =
      try do
        Druid.Supervisors.sync(repo, sync_opts)
      rescue
        error in [Druid.Supervisors.Error, ArgumentError] -> Mix.raise(Exception.message(error))
      end

    Enum.each(results, &report/1)

    errors = Enum.count(results, &(elem(&1, 0) == :error))

    if errors > 0 do
      Mix.raise("#{errors} supervisor request(s) failed")
    end
  end

  defp report({:error, %Druid.Supervisors.Spec{} = spec, error}) do
    Mix.shell().error("failed        #{label(spec)}\n  #{Exception.message(error)}")
  end

  defp report({:error, id, error}) do
    Mix.shell().error("failed        #{id}\n  #{Exception.message(error)}")
  end

  defp report({status, %Druid.Supervisors.Spec{} = spec}) do
    Mix.shell().info(String.pad_trailing(describe(status), 14) <> label(spec))
  end

  defp report({status, id}) do
    Mix.shell().info(String.pad_trailing(describe(status), 14) <> id)
  end

  defp label(%{name: name, id: name}), do: name
  defp label(%{name: name, id: id}), do: "#{name} (supervisor #{id})"

  defp describe(:created), do: "created"
  defp describe(:updated), do: "updated"
  defp describe(:unchanged), do: "unchanged"
  defp describe(:restarted), do: "restarted"
  defp describe(:terminated), do: "terminated"
  defp describe(:would_create), do: "would create"
  defp describe(:would_update), do: "would submit"
  defp describe(:would_terminate), do: "would stop"
end
