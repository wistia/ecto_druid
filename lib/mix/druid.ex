defmodule Mix.Druid do
  @moduledoc false

  @doc """
  Loads config (including runtime.exs) and returns the Druid repo to use.

  Uses `-r`/`--repo` if given. Otherwise picks the Druid repos from the app's
  `:ecto_repos`, and requires exactly one.
  """
  def setup!(args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    case Enum.filter(Mix.Ecto.parse_repo(args), &druid_repo?/1) do
      [repo] ->
        repo

      [] ->
        Mix.raise(
          "No Druid repo found. Pass one with -r MyApp.DruidRepo, or add it to " <>
            "the :ecto_repos config of your app"
        )

      repos ->
        Mix.raise(
          "Found several Druid repos (#{Enum.map_join(repos, ", ", &inspect/1)}). " <>
            "Pick one with -r"
        )
    end
  end

  defp druid_repo?(repo) do
    Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) and
      repo.__adapter__() == Ecto.Adapters.Druid
  end

  @doc "Splits a comma-separated `--only` value into spec names."
  def only(opts) do
    case Keyword.get_values(opts, :only) do
      [] -> []
      values -> [only: Enum.flat_map(values, &String.split(&1, ",", trim: true))]
    end
  end
end
