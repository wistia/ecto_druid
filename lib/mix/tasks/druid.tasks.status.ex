defmodule Mix.Tasks.Druid.Tasks.Status do
  @shortdoc "Shows the status of recorded Druid tasks"

  @moduledoc """
  Shows the status of the tasks recorded by `mix druid.tasks.backfill`, or of
  task IDs given directly, and optionally waits for them.

      mix druid.tasks.status tmp/druid/backfills/page_views-20261115T120000Z.jsonl
      mix druid.tasks.status tmp/druid/backfills/page_views-20261115T120000Z.jsonl --wait
      mix druid.tasks.status index_parallel_page_views_abc_2026-11-15T12:00:00.000Z

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--wait` - Wait for the tasks to finish.
    * `--wait-for-segments` - With `--wait`, also wait until the segments
      are loaded.
    * `--timeout` - Stop waiting after this many seconds.

  Exits with a non-zero status if any task failed (or, with `--wait`, didn't
  finish in time).
  """

  use Mix.Task

  @switches [repo: :keep, wait: :boolean, wait_for_segments: :boolean, timeout: :integer]
  @aliases [r: :repo]

  @impl true
  def run(args) do
    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    if argv == [], do: Mix.raise("Expected a tasks file or task IDs")

    runs = Enum.flat_map(argv, &read_runs/1)
    repo = Mix.Druid.setup!(args)

    if Keyword.get(opts, :wait, false) do
      Druid.Tasks.await_all(
        repo,
        runs,
        Mix.Druid.wait_opts(opts) ++ [on_progress: &Mix.Druid.print_progress/1]
      )
      |> Mix.Druid.report_runs!()
    else
      runs = Druid.Tasks.statuses(repo, runs)
      Enum.each(runs, &print_run/1)
      Mix.Druid.print_progress(Druid.Tasks.progress(runs))

      if Enum.any?(runs, & &1.error), do: Mix.raise("Some tasks failed")
    end
  end

  defp read_runs(arg) do
    if File.regular?(arg) do
      arg
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.map(&(&1 |> Jason.decode!() |> Druid.Tasks.Run.from_map()))
    else
      [%Druid.Tasks.Run{task_id: arg}]
    end
  end

  defp print_run(run) do
    state =
      cond do
        run.error && run.status -> run.status["status"]
        run.error -> "ERROR"
        run.status -> run.status["status"]
        true -> "UNKNOWN"
      end

    Mix.shell().info(String.pad_trailing(state, 10) <> Mix.Druid.run_label(run))
  end
end
