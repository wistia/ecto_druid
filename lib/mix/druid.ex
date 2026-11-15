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

  @doc """
  Prints rendered templates, or writes each to `<out>/<name>.json`.
  `header` returns the comment line printed above each one.
  """
  def print_rendered(items, out, header, body) do
    case out do
      nil ->
        Enum.each(items, fn item ->
          Mix.shell().info("# " <> header.(item))
          Mix.shell().info(Jason.encode!(body.(item), pretty: true))
        end)

      out ->
        Enum.each(items, fn item ->
          path = Path.join(out, item.name <> ".json")
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, Jason.encode!(body.(item), pretty: true) <> "\n")
          Mix.shell().info("Wrote #{path}")
        end)
    end
  end

  @doc """
  Prints one line per sync result and raises if any failed. `label` turns a
  result's subject into text.
  """
  def report_results!(results, label, what) do
    Enum.each(results, fn
      {:error, subject, error} ->
        Mix.shell().error(
          String.pad_trailing("failed", 14) <>
            label.(subject) <> "\n  " <> Exception.message(error)
        )

      {status, subject} ->
        Mix.shell().info(String.pad_trailing(describe(status), 14) <> label.(subject))
    end)

    errors = Enum.count(results, &(elem(&1, 0) == :error))

    if errors > 0 do
      Mix.raise("#{errors} #{what} failed")
    end
  end

  defp describe(status), do: status |> Atom.to_string() |> String.replace("_", " ")
end
