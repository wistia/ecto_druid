defmodule Mix.Tasks.Druid.Supervisors.Render do
  @shortdoc "Renders Druid supervisor spec templates"

  @moduledoc """
  Renders the supervisor spec templates for a Druid repo and prints them, or
  writes them to a directory. Nothing is sent to Druid.

      mix druid.supervisors.render
      mix druid.supervisors.render --only page_views_hourly
      mix druid.supervisors.render --out tmp/supervisors

  Config is loaded the same way as when the app starts, including
  `config/runtime.exs`, so environment variables apply. See `Druid.Supervisors`
  for the template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--only` - Render only these specs (comma-separated, or repeated).
    * `--out` - Write each spec to `<out>/<name>.json` instead of printing.
  """

  use Mix.Task

  @switches [repo: :keep, only: :keep, out: :string]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    repo = Mix.Druid.setup!(args)

    specs =
      try do
        Druid.Supervisors.render(repo, Mix.Druid.only(opts))
      rescue
        error in Druid.Supervisors.Error -> Mix.raise(Exception.message(error))
      end

    case opts[:out] do
      nil ->
        Enum.each(specs, fn spec ->
          Mix.shell().info("# #{spec.name} (supervisor #{spec.id})")
          Mix.shell().info(Jason.encode!(spec.spec, pretty: true))
        end)

      out ->
        Enum.each(specs, fn spec ->
          path = Path.join(out, spec.name <> ".json")
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, Jason.encode!(spec.spec, pretty: true) <> "\n")
          Mix.shell().info("Wrote #{path}")
        end)
    end
  end
end
