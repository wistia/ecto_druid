defmodule Mix.Tasks.Druid.Tasks.Run do
  @shortdoc "Submits a Druid task and waits for it"

  @moduledoc """
  Renders a task spec template, submits it to Druid, and waits for the task to
  finish.

      mix druid.tasks.run backfill_page_views --assign interval=2026-11-01/P1D
      mix druid.tasks.run backfill_page_views --wait-for-segments
      mix druid.tasks.run backfill_page_views --no-wait

  Each run submits a new task, so running a batch ingestion task twice
  ingests its data twice (or replaces it, depending on the spec). In a
  release, call `Druid.Tasks.run/3` instead. See `Druid.Tasks` for the
  template format and configuration.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--assign` - Set an assign for this run, as `key=value` (repeatable).
      Values are strings, so render them with `json @key`.
    * `--no-wait` - Print the task ID and exit without waiting.
    * `--wait-for-segments` - After the task succeeds, also wait until its
      segments are loaded and can be queried.
    * `--timeout` - Give up waiting after this many seconds. Defaults to
      waiting as long as the task runs. The task keeps running either way.

  Exits with a non-zero status if the task fails or times out.
  """

  use Mix.Task

  @switches [
    repo: :keep,
    assign: :keep,
    wait: :boolean,
    wait_for_segments: :boolean,
    timeout: :integer
  ]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    name =
      case argv do
        [name] -> name
        _ -> Mix.raise("Expected one task template name, e.g. mix druid.tasks.run my_task")
      end

    repo = Mix.Druid.setup!(args)

    task_id =
      try do
        Druid.Tasks.submit(repo, name, Mix.Druid.assigns(opts))
      rescue
        error in Druid.Tasks.Error -> Mix.raise(Exception.message(error))
      end
      |> case do
        {:ok, task_id} -> task_id
        {:error, error} -> Mix.raise("Failed to submit #{name}: #{Exception.message(error)}")
      end

    Mix.shell().info("Submitted #{name} as task #{task_id}")

    if Keyword.get(opts, :wait, true), do: await(repo, task_id, opts)
  end

  defp await(repo, task_id, opts) do
    case Druid.Tasks.await(repo, task_id, Mix.Druid.wait_opts(opts)) do
      {:ok, status} ->
        Mix.shell().info("Task #{task_id} succeeded#{duration(status)}")

      {:error, error} ->
        Mix.raise(Exception.message(error))
    end
  end

  defp duration(%{"duration" => ms}) when is_integer(ms) and ms >= 0,
    do: " in #{Float.round(ms / 1000, 1)}s"

  defp duration(_status), do: ""
end
