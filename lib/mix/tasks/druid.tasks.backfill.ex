defmodule Mix.Tasks.Druid.Tasks.Backfill do
  @shortdoc "Runs a Druid task template once per interval over a range"

  @moduledoc """
  Renders a backfill template once per day (or other step) from `--from` to
  `--to`, submits the tasks, and waits for them. Backfill templates live in
  `priv/druid/backfills`, or the `:path` under the repo's `:backfills`
  config.

      mix druid.tasks.backfill page_views --from 2026-10-01 --to 2026-11-01 --dry-run
      mix druid.tasks.backfill page_views --from 2026-10-01 --to 2026-11-01 --out tmp/backfill
      mix druid.tasks.backfill page_views --from 2026-10-01 --to 2026-11-01 --concurrency 4

  Each task's template gets `@interval`, `@start` and `@stop`. See "Backfills"
  in `Druid.Tasks`.

  Submitted task IDs are recorded, one JSON object per line, in a file under
  `tmp/druid/backfills` (or `--tasks-file`). If you stop waiting, check on them
  later with `mix druid.tasks.status FILE`.

  ## Options

    * `-r`, `--repo` - The Druid repo. Defaults to the only Druid repo in the
      app's `:ecto_repos`.
    * `--from`, `--to` - The range to backfill, as ISO 8601 dates or
      date-times. `--to` is exclusive. Required.
    * `--step` - `hour`, `day`, `week` or `month`, optionally with a count
      such as `6hour`. Defaults to `day`.
    * `--time-zone` - The time zone of `--from`, `--to` and the step
      boundaries. Zones other than UTC need a time zone database.
    * `--concurrency` - Run at most this many tasks at once.
    * `--assign` - Set an assign, as `key=value` (repeatable).
    * `--dry-run` - List the intervals without submitting anything.
    * `--out` - With `--dry-run`, also write each task to
      `<out>/<name>/<interval start>.json`.
    * `--tasks-file` - Where to record submitted task IDs.
    * `--no-wait` - Exit once every task is submitted.
    * `--wait-for-segments` - After every task succeeds, also wait until the
      segments are loaded.
    * `--timeout` - Stop waiting after this many seconds. Tasks keep running.

  Exits with a non-zero status if any task fails, times out or can't be
  submitted.
  """

  use Mix.Task

  @switches [
    repo: :keep,
    from: :string,
    to: :string,
    step: :string,
    time_zone: :string,
    concurrency: :integer,
    assign: :keep,
    dry_run: :boolean,
    out: :string,
    tasks_file: :string,
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
        _ -> Mix.raise("Expected one task template name, e.g. mix druid.tasks.backfill my_task")
      end

    from = opts[:from] || Mix.raise("--from is required")
    to = opts[:to] || Mix.raise("--to is required")
    dry_run? = Keyword.get(opts, :dry_run, false)

    if opts[:out] && not dry_run?, do: Mix.raise("--out can only be used with --dry-run")

    repo = Mix.Druid.setup!(args)

    tasks_file =
      unless dry_run?, do: opts[:tasks_file] || default_tasks_file(name)

    backfill_opts =
      Mix.Druid.assigns(opts) ++
        Mix.Druid.wait_opts(opts) ++
        Keyword.take(opts, [:time_zone, :concurrency, :dry_run]) ++
        [
          step: parse_step(opts[:step] || "day"),
          await: Keyword.get(opts, :wait, true),
          on_submit: &record(&1, tasks_file),
          on_progress: &Mix.Druid.print_progress/1
        ]

    if tasks_file do
      File.mkdir_p!(Path.dirname(tasks_file))
      File.write!(tasks_file, "")
      Mix.shell().info("Recording task IDs in #{tasks_file}")
    end

    runs =
      try do
        Druid.Tasks.backfill(repo, name, from, to, backfill_opts)
      rescue
        error in [Druid.Tasks.Error, ArgumentError] -> Mix.raise(Exception.message(error))
      end

    if dry_run? do
      print_dry_run(runs, opts[:out])
    else
      Mix.Druid.report_runs!(runs)
    end
  end

  defp parse_step(step) do
    case Regex.run(~r/^(\d*)(hour|day|week|month)$/, step) do
      [_, "", unit] -> String.to_atom(unit)
      [_, count, unit] -> {String.to_integer(count), String.to_atom(unit)}
      nil -> Mix.raise("--step must be hour, day, week or month, optionally with a count")
    end
  end

  defp default_tasks_file(name) do
    stamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    Path.join("tmp/druid/backfills", "#{String.replace(name, "/", "_")}-#{stamp}.jsonl")
  end

  defp record(_run, nil), do: :ok

  defp record(run, tasks_file) do
    File.write!(tasks_file, Jason.encode!(Druid.Tasks.Run.to_map(run)) <> "\n", [:append])
  end

  defp print_dry_run(runs, out) do
    Enum.each(runs, fn run ->
      line = "would submit  #{run.interval}"

      case out do
        nil ->
          Mix.shell().info(line)

        out ->
          start = run.interval.start |> DateTime.to_iso8601() |> String.replace(":", "")
          path = Path.join([out, run.name, start <> ".json"])
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, Jason.encode!(run.spec, pretty: true) <> "\n")
          Mix.shell().info(line <> " -> " <> path)
      end
    end)

    Mix.shell().info("#{length(runs)} task(s), nothing submitted")
  end
end
