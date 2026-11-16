defmodule Druid.Tasks do
  @moduledoc """
  Runs Druid tasks, such as batch ingestion (`index_parallel`), and waits for
  them to finish. Task specs can live in your application as EEx templates,
  with values from config and from the caller.

  ## Waiting for a task

  `await/3` polls a task until it succeeds or fails. It works on any task ID,
  including SQL-based ingestion queries submitted with
  `Druid.Client.SQL.insert/3`:

      %{"taskId" => task_id} =
        Druid.Client.SQL.insert("INSERT INTO page_views SELECT ... PARTITIONED BY DAY")
        |> Druid.Client.request!(host: "localhost", port: 8888)

      {:ok, %{"status" => "SUCCESS"}} = Druid.Tasks.await(MyApp.DruidRepo, task_id)

  A task's segments can be queried once Historicals have loaded them, shortly
  after the task succeeds. Pass `wait_for_segments: true` to wait for that too.

  ## Templates

  Each `*.json.eex` file in the templates directory (default
  `priv/druid/tasks`, searched recursively) is one task spec. Templates use
  the same format and helpers as supervisor specs, including `data_schema`
  (see `Druid.Supervisors`):

      {
        "type": "index_parallel",
        "spec": {
          "ioConfig": {
            "type": "index_parallel",
            "inputSource": {"type": "s3", "prefixes": [<%= json @source_prefix %>]},
            "inputFormat": {"type": "json"}
          },
          "tuningConfig": {"type": "index_parallel", "maxNumConcurrentSubTasks": <%= @subtasks %>},
          "dataSchema": <%= data_schema MyApp.PageViewsHourly,
                              segment_granularity: "DAY",
                              intervals: [@interval] %>
        }
      }

  Plain `*.json` files are picked up too, and files whose name starts with
  `_` are partials.

  Unlike supervisors, tasks run once rather than being kept in sync, so
  templates often need values that change from run to run, such as the
  interval to backfill. Pass them as `:assigns` when running the task. They
  are deep-merged over the configured assigns:

      Druid.Tasks.run(MyApp.DruidRepo, "backfill_page_views",
        assigns: %{interval: "2026-11-01/2026-11-02"}
      )

  Submitting the same batch ingestion task twice ingests its data twice, or
  replaces it, depending on the task's `appendToExisting`. There is no
  `sync`.

  ## Backfills

  To reprocess a range of time, run a template once per day (or hour, week
  or month) with `backfill/5`. Splitting a backfill up keeps each task small
  and lets a failed day be retried on its own:

      Druid.Tasks.backfill(MyApp.DruidRepo, "page_views", ~D[2026-10-01], ~D[2026-11-01],
        step: :day,
        concurrency: 4
      )

  Each task is rendered with these assigns, on top of the usual ones:

    * `@interval` - The `Ecto.Druid.Interval` the task covers. Pass it to
      `data_schema`'s `:intervals` so a task that doesn't append replaces
      exactly that interval.
    * `@start` and `@stop` - Its bounds, as UTC `DateTime`s.

  When the input is stored in time-partitioned paths, `partition_prefixes`
  lists the ones an interval covers:

      "inputSource": {
        "type": "s3",
        "prefixes": <%= partition_prefixes "s3://my-bucket/page_views", @interval,
                          "year=%Y/month=%m/day=%d/" %>
      },
      ...
      "dataSchema": <%= data_schema MyApp.PageViews, intervals: [@interval] %>,
      "ioConfig": {"appendToExisting": false, ...}

  Druid replaces whole segments, so make sure each task's input holds all of
  the data for its interval, not just the part being fixed. For the same
  reason, don't use a `:step` shorter than the data source's segment
  granularity: Druid widens each task's intervals to whole segments, so a
  6-hour task on a data source with `DAY` segments would replace the whole
  day with 6 hours of data.

  Rows outside a task's `intervals` are skipped, so tasks can share input
  that overlaps their interval, such as the two UTC days a local day spans.

  Days start at midnight UTC unless you pass `:time_zone`. Zones other than
  UTC need a time zone database, such as `:tz` or `:tzdata`, configured with
  `config :elixir, :time_zone_database, ...`. A day in a zone can span two UTC
  days, which `partition_prefixes` accounts for.

  ## Configuration

  Configure tasks under the `:tasks` key of your Druid repo's config:

      config :my_app, MyApp.DruidRepo,
        host: System.get_env("DRUID_BROKER_HOST", "localhost"),
        port: 8082,
        tasks: [
          # The tasks API lives on the Router/Overlord, not the Broker.
          # These default to the repo's :host, :port and :scheme.
          host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
          port: 8888,
          assigns: %{source_prefix: System.get_env("PAGE_VIEWS_PREFIX"), subtasks: 1},
          specs: %{"backfill_page_views" => %{subtasks: 4}}
        ]

  The supported options are:

    * `:path` - The templates directory. A relative path is resolved against
      the repo's OTP app directory. Defaults to `"priv/druid/tasks"`.
    * `:assigns` - Assigns available to every template.
    * `:specs` - A map of template name to assigns for that template only.
    * `:host`, `:port`, `:scheme` - Where to send task API requests. Default
      to the repo's values.

  Every option can also be given to the functions in this module directly.
  `:assigns` given that way are deep-merged over the configured ones; other
  options replace them.

  ## Running tasks

  In development, use the Mix tasks:

      mix druid.tasks.render backfill_page_views --assign interval=2026-11-01/P1D
      mix druid.tasks.run backfill_page_views --assign interval=2026-11-01/P1D
      mix druid.tasks.backfill page_views --from 2026-10-01 --to 2026-11-01 --concurrency 4
      mix druid.tasks.status tmp/druid/backfills/page_views-20261115T120000Z.jsonl

  In a release, call `run/3` from your release module:

      defmodule MyApp.Release do
        def backfill_page_views(from, to) do
          Application.load(:my_app)
          {:ok, _} = Application.ensure_all_started(:req)

          runs = Druid.Tasks.backfill(MyApp.DruidRepo, "page_views", from, to, concurrency: 4)
          Enum.all?(runs, &Druid.Tasks.Run.succeeded?/1) || raise "backfill failed"
        end
      end
  """

  alias Druid.SpecTemplates

  defmodule Spec do
    @moduledoc """
    A rendered task spec.

      * `:name` - The template's path relative to the templates directory,
        without its extension.
      * `:path` - The template's absolute path.
      * `:data_source` - The data source the task writes to, if the spec
        names one.
      * `:spec` - The rendered spec, decoded from JSON.
      * `:interval` - For a backfill, the `Ecto.Druid.Interval` it was
        rendered for.
    """
    @type t :: %__MODULE__{
            name: String.t(),
            path: Path.t(),
            data_source: String.t() | nil,
            spec: map(),
            interval: Ecto.Druid.Interval.t() | nil
          }
    defstruct [:name, :path, :data_source, :spec, :interval]
  end

  defmodule Run do
    @moduledoc """
    One task of a backfill, or one task passed to `Druid.Tasks.await_all/3`.

      * `:name` - The template name, if it came from one.
      * `:interval` - The `Ecto.Druid.Interval` it covers, for a backfill.
      * `:data_source` - The data source it writes to, if known.
      * `:spec` - The rendered task spec, until it's submitted.
      * `:task_id` - The task's ID once submitted.
      * `:status` - The task's last status from Druid.
      * `:error` - Why the task didn't succeed: a `Druid.Tasks.Error` when
        it failed or timed out, or a request exception. `nil` otherwise.

    `to_map/1` and `from_map/1` convert runs to and from the JSON that
    `mix druid.tasks.backfill` records, so they can be checked on later.
    """
    @type t :: %__MODULE__{
            name: String.t() | nil,
            interval: Ecto.Druid.Interval.t() | nil,
            data_source: String.t() | nil,
            spec: map() | nil,
            task_id: String.t() | nil,
            status: map() | nil,
            error: Exception.t() | nil
          }
    defstruct [:name, :interval, :data_source, :spec, :task_id, :status, :error]

    @doc "Returns `true` if the task succeeded."
    @spec succeeded?(t()) :: boolean()
    def succeeded?(%__MODULE__{error: nil, status: %{"status" => "SUCCESS"}}), do: true
    def succeeded?(%__MODULE__{}), do: false

    @doc "Encodes the run's name, interval, data source and task ID as a map."
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = run) do
      %{
        "name" => run.name,
        "interval" => run.interval && Ecto.Druid.Interval.to_iso8601(run.interval),
        "dataSource" => run.data_source,
        "task" => run.task_id
      }
    end

    @doc "Builds a run from a map made by `to_map/1`."
    @spec from_map(map()) :: t()
    def from_map(%{"task" => task_id} = map) when is_binary(task_id) do
      interval =
        case map["interval"] do
          nil ->
            nil

          string ->
            [start, stop] = String.split(string, "/", parts: 2)
            Ecto.Druid.Interval.new(start, stop)
        end

      %__MODULE__{
        name: map["name"],
        interval: interval,
        data_source: map["dataSource"],
        task_id: task_id
      }
    end
  end

  defmodule Error do
    @moduledoc """
    Raised when a task template can't be rendered, and returned when a task
    fails or doesn't finish in time.

      * `:reason` - `:failed` or `:timeout` for a task, `nil` for a template
        error.
      * `:task_id` - The task's ID, when there is one.
      * `:status` - The task's last status, when there is one.
    """
    @type t :: %__MODULE__{
            message: String.t(),
            reason: :failed | :timeout | nil,
            task_id: String.t() | nil,
            status: map() | nil
          }
    defexception [:message, :reason, :task_id, :status]
  end

  @default_path "priv/druid/tasks"
  @default_poll_interval 2_000
  # The Coordinator only reports on the last two weeks of segments unless
  # given an interval.
  @all_time "1000-01-01/3000-01-01"

  @doc """
  Renders the task templates for `repo`.

  Raises `Druid.Tasks.Error` if a template fails to render (for example
  because an assign is missing) or isn't a JSON object.

  ## Options

    * `:only` - A list of template names to render. Defaults to all of them.
    * `:assigns` - Assigns for this call, deep-merged over the configured
      ones.
    * any option from the "Configuration" section of the module docs.
  """
  @spec render(Ecto.Repo.t(), Keyword.t()) :: [Spec.t()]
  def render(repo, opts \\ []) do
    config = config(repo, opts)
    root = SpecTemplates.root!(repo, config, @default_path, Error, "task")

    root
    |> SpecTemplates.discover()
    |> SpecTemplates.filter_only(Keyword.get(opts, :only), Error, "task")
    |> Enum.map(&render_spec(&1, root, config))
  end

  @doc """
  Submits a task to Druid and returns its ID without waiting for it.

  `task` is a template name, a `Druid.Tasks.Spec` from `render/2`, or a task
  spec as a map. Templates are rendered first, so this raises
  `Druid.Tasks.Error` when one can't be rendered. Request errors are returned.

  Takes the same options as `render/2`.
  """
  @spec submit(Ecto.Repo.t(), String.t() | Spec.t() | map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def submit(repo, task, opts \\ []) do
    spec = task_spec(repo, task, opts)

    case Druid.Client.Task.submit(spec) |> Druid.Client.request(request_opts(repo, opts)) do
      {:ok, %{"task" => task_id}} -> {:ok, task_id}
      {:ok, body} -> {:error, %Error{message: "unexpected response from Druid: #{inspect(body)}"}}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Waits for a task to finish.

  Returns `{:ok, status}` when the task succeeds, where `status` is the
  status map Druid reports (`"id"`, `"status"`, `"duration"`,
  `"dataSource"`, and so on). Returns `{:error, %Druid.Tasks.Error{}}` when it
  fails or times out, and `{:error, exception}` when a request fails.

  ## Options

    * `:timeout` - How long to wait in milliseconds, including for segments
      to load. Defaults to `:infinity`.
    * `:poll_interval` - How often to check, in milliseconds. Defaults to
      `#{@default_poll_interval}`.
    * `:wait_for_segments` - When `true`, also wait until Historicals have
      loaded the data source's segments, so the new data can be queried.
      Defaults to `false`.
    * `:data_source` - The data source to wait for segments of. Defaults to
      the one in the task's status.
    * `:segments_interval` - Only wait for segments in this interval. Defaults
      to all of them.
    * `:host`, `:port`, `:scheme` - As in the "Configuration" section of the
      module docs.
  """
  @spec await(Ecto.Repo.t(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, Exception.t()}
  def await(repo, task_id, opts \\ []) do
    request_opts = request_opts(repo, opts)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)

    deadline = deadline(Keyword.get(opts, :timeout, :infinity))

    with {:ok, status} <-
           poll(deadline, poll_interval, fn -> check_task(task_id, request_opts) end) ||
             {:error, timeout_error(task_id, nil, "task #{task_id}")},
         {:ok, status} <- check_failed(task_id, status) do
      if Keyword.get(opts, :wait_for_segments, false) do
        await_segments(task_id, status, deadline, poll_interval, request_opts, opts)
      else
        {:ok, status}
      end
    end
  end

  @doc """
  Submits a task and waits for it to finish. Combines `submit/3` and
  `await/3`, and takes the options of both.
  """
  @spec run(Ecto.Repo.t(), String.t() | Spec.t() | map(), Keyword.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def run(repo, task, opts \\ []) do
    with {:ok, task_id} <- submit(repo, task, opts) do
      await(repo, task_id, opts)
    end
  end

  @doc """
  Renders a template once per interval from `from` to `to`, submits the
  tasks, and waits for them. See "Backfills" in the module docs.

  Templates are all rendered before anything is submitted, so a template
  error raises `Druid.Tasks.Error` without starting any tasks. Returns one
  `Druid.Tasks.Run` per interval, in order. A run whose `:error` is set
  failed, timed out or couldn't be submitted; the others still ran.

  ## Options

    * `:step` - The length of each task's interval: `:hour`, `:day`,
      `:week`, `:month`, or a `{count, unit}` tuple such as `{6, :hour}`.
      Defaults to `:day`. The last interval stops at `to`.
    * `:time_zone` - The time zone `from`, `to` and step boundaries are in.
      Defaults to `"Etc/UTC"`.
    * `:concurrency` - Run at most this many of the backfill's tasks at once,
      submitting the next as each finishes, so a backfill doesn't take every
      worker slot from streaming ingestion. Defaults to submitting them all
      and letting Druid queue them.
    * `:await` - Wait for the tasks to finish. Defaults to `true`. With
      `false`, this still waits as long as `:concurrency` needs to submit
      every task.
    * `:dry_run` - Render the tasks without submitting them. The runs' `:spec`
      holds each one.
    * `:on_submit` - Called with each `Druid.Tasks.Run` once it has a task
      ID, for example to record it.
    * `:on_progress` - Called with a map of `:total`, `:succeeded`, `:failed`,
      `:running` and `:pending` (not yet submitted) counts whenever they
      change.
    * `:wait_for_segments` - After every task succeeds, also wait until the
      backfilled segments are loaded.
    * `:timeout`, `:poll_interval` - As in `await/3`, for the whole backfill.
    * `:assigns` and the other options of `render/2`.

  `from` and `to` are `Date`s, `DateTime`s, `NaiveDateTime`s or ISO 8601
  strings. `to` is exclusive.
  """
  @spec backfill(Ecto.Repo.t(), String.t(), term(), term(), Keyword.t()) :: [Run.t()]
  def backfill(repo, name, from, to, opts \\ []) do
    runs =
      from
      |> intervals(to, Keyword.take(opts, [:step, :time_zone]))
      |> Enum.map(fn interval ->
        spec = render_interval(repo, name, interval, opts)

        %Run{
          name: name,
          interval: interval,
          data_source: spec.data_source,
          spec: spec.spec
        }
      end)

    if Keyword.get(opts, :dry_run, false) do
      runs
    else
      request_opts = request_opts(repo, opts)

      runs
      |> Druid.Tasks.Batch.run(request_opts, batch_opts(opts))
      |> maybe_await_segments(request_opts, opts)
    end
  end

  @doc """
  Waits for several tasks at once, checking them all in one request each
  poll.

  `runs` are `Druid.Tasks.Run`s (for example from `backfill/5` with
  `await: false`, or read back with `Druid.Tasks.Run.from_map/1`) or task
  IDs. Returns the runs with their final `:status`, and `:error` set on any
  that failed or timed out.

  ## Options

    * `:on_progress`, `:wait_for_segments` - As in `backfill/5`. Waiting for
      segments needs each run's `:data_source`, or a `:data_source` option.
    * `:timeout`, `:poll_interval`, `:segments_interval`, `:data_source` -
      As in `await/3`.
  """
  @spec await_all(Ecto.Repo.t(), [Run.t() | String.t()], Keyword.t()) :: [Run.t()]
  def await_all(repo, runs, opts \\ []) do
    request_opts = request_opts(repo, opts)

    runs
    |> Enum.map(&to_run/1)
    |> Druid.Tasks.Batch.run(request_opts, batch_opts(opts))
    |> maybe_await_segments(request_opts, opts)
  end

  @doc """
  Fetches the current status of several tasks in one request, without
  waiting. Takes and returns `Druid.Tasks.Run`s or task IDs, like
  `await_all/3`.
  """
  @spec statuses(Ecto.Repo.t(), [Run.t() | String.t()], Keyword.t()) :: [Run.t()]
  def statuses(repo, runs, opts \\ []) do
    runs |> Enum.map(&to_run/1) |> Druid.Tasks.Batch.refresh(request_opts(repo, opts))
  end

  @doc """
  Counts runs by state. Returns a map of `:total`, `:succeeded`, `:failed`,
  `:running` and `:pending` (not yet submitted).
  """
  @spec progress([Run.t()]) :: %{atom() => non_neg_integer()}
  def progress(runs), do: Druid.Tasks.Batch.progress(runs)

  @doc """
  Splits the time from `from` to `to` into consecutive intervals, as
  `backfill/5` does. Takes its `:step` and `:time_zone` options.

      iex> Druid.Tasks.intervals(~D[2026-11-01], ~D[2026-11-03]) |> Enum.map(&to_string/1)
      ["2026-11-01T00:00:00Z/2026-11-02T00:00:00Z", "2026-11-02T00:00:00Z/2026-11-03T00:00:00Z"]
  """
  @spec intervals(term(), term(), Keyword.t()) :: [Ecto.Druid.Interval.t()]
  def intervals(from, to, opts \\ []), do: Druid.Tasks.Intervals.split(from, to, opts)

  @doc """
  Lists the time-partitioned storage prefixes that hold `interval`'s data,
  one per UTC hour or day the interval touches. `format` is a
  `Calendar.strftime/2` format appended to `base`.

      iex> Druid.Tasks.partition_prefixes(
      ...>   "s3://bucket/events",
      ...>   "2026-11-01T05:00:00Z/2026-11-02T05:00:00Z",
      ...>   "year=%Y/month=%m/day=%d/"
      ...> )
      ["s3://bucket/events/year=2026/month=11/day=01/", "s3://bucket/events/year=2026/month=11/day=02/"]

  ## Options

    * `:step` - `:hour` or `:day`. Defaults to `:hour` when `format` contains
      `%H`, and `:day` otherwise.
  """
  @spec partition_prefixes(
          String.t(),
          Ecto.Druid.Interval.t() | String.t(),
          String.t(),
          Keyword.t()
        ) ::
          [String.t()]
  def partition_prefixes(base, interval, format, opts \\ []),
    do: Druid.Tasks.Intervals.partition_prefixes(base, interval, format, opts)

  @doc """
  Returns the data source a task spec writes to, or `nil`.

  This is `spec.dataSchema.dataSource` for ingestion tasks and `dataSource`
  for tasks such as `compact` and `kill`.
  """
  @spec data_source(map()) :: String.t() | nil
  def data_source(%{"spec" => %{"dataSchema" => %{"dataSource" => ds}}}) when is_binary(ds),
    do: ds

  def data_source(%{"dataSource" => ds}) when is_binary(ds), do: ds
  def data_source(_spec), do: nil

  defp config(repo, opts) do
    config = SpecTemplates.config(repo, :tasks, Keyword.delete(opts, :assigns))

    assigns =
      config
      |> Keyword.get(:assigns, %{})
      |> SpecTemplates.to_map()
      |> SpecTemplates.deep_merge(opts |> Keyword.get(:assigns, %{}) |> SpecTemplates.to_map())

    Keyword.put(config, :assigns, assigns)
  end

  defp request_opts(repo, opts),
    do: SpecTemplates.request_opts(repo, SpecTemplates.config(repo, :tasks, opts))

  defp task_spec(repo, name, opts) when is_binary(name) do
    [spec] = render(repo, Keyword.put(opts, :only, [name]))
    spec.spec
  end

  defp task_spec(_repo, %Spec{spec: spec}, _opts), do: spec
  defp task_spec(_repo, %{} = spec, _opts), do: spec

  defp render_spec({name, path}, root, config) do
    case SpecTemplates.render!(name, path, root, config, Error) do
      %{} = spec -> %Spec{name: name, path: path, data_source: data_source(spec), spec: spec}
      _ -> raise Error, "#{name} must render a JSON object"
    end
  end

  defp render_interval(repo, name, interval, opts) do
    interval_assigns = %{interval: interval, start: interval.start, stop: interval.stop}

    assigns =
      opts
      |> Keyword.get(:assigns, %{})
      |> SpecTemplates.to_map()
      |> Map.merge(interval_assigns)

    [spec] = render(repo, Keyword.merge(opts, only: [name], assigns: assigns))
    %{spec | interval: interval}
  end

  defp batch_opts(opts) do
    opts
    |> Keyword.take([:concurrency, :await, :timeout, :on_submit, :on_progress])
    |> Keyword.put(:poll_interval, Keyword.get(opts, :poll_interval, @default_poll_interval))
  end

  defp to_run(%Run{} = run), do: run
  defp to_run(task_id) when is_binary(task_id), do: %Run{task_id: task_id}

  defp maybe_await_segments(runs, request_opts, opts) do
    waiting? = Keyword.get(opts, :wait_for_segments, false) and Keyword.get(opts, :await, true)

    if waiting? and Enum.all?(runs, &Run.succeeded?/1) do
      poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
      deadline = deadline(Keyword.get(opts, :timeout, :infinity))

      runs
      |> Enum.group_by(&(Keyword.get(opts, :data_source) || &1.data_source))
      |> Enum.reduce(runs, fn {data_source, group}, runs ->
        case await_group_segments(data_source, group, deadline, poll_interval, request_opts, opts) do
          :ok ->
            runs

          {:error, error} ->
            ids = MapSet.new(group, & &1.task_id)
            Enum.map(runs, &if(&1.task_id in ids, do: %{&1 | error: error}, else: &1))
        end
      end)
    else
      runs
    end
  end

  defp await_group_segments(nil, _group, _deadline, _poll_interval, _request_opts, _opts) do
    {:error, %Error{message: "can't wait for segments of tasks with no data source"}}
  end

  defp await_group_segments(data_source, group, deadline, poll_interval, request_opts, opts) do
    interval = Keyword.get_lazy(opts, :segments_interval, fn -> covering_interval(group) end)
    check = fn -> check_segments(data_source, interval, request_opts) end

    case poll(deadline, poll_interval, check) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
      nil -> {:error, timeout_error(nil, nil, "segments of #{data_source} to load")}
    end
  end

  # From the earliest start to the latest stop, when every run has an
  # interval with DateTime bounds.
  defp covering_interval(runs) do
    bounds =
      for %Run{interval: %{start: %DateTime{} = a, stop: %DateTime{} = b}} <- runs, do: {a, b}

    if bounds != [] and length(bounds) == length(runs) do
      {starts, stops} = Enum.unzip(bounds)

      Ecto.Druid.Interval.new(Enum.min(starts, DateTime), Enum.max(stops, DateTime))
      |> Ecto.Druid.Interval.to_iso8601()
    else
      @all_time
    end
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp check_task(task_id, request_opts) do
    case Druid.Client.Task.status(task_id) |> Druid.Client.request(request_opts) do
      {:ok, %{"status" => %{"status" => state} = status}} when state in ["SUCCESS", "FAILED"] ->
        {:done, status}

      {:ok, _running} ->
        :wait

      {:error, error} ->
        {:error, error}
    end
  end

  defp check_failed(task_id, %{"status" => "FAILED"} = status) do
    message =
      case status["errorMsg"] do
        nil -> "task #{task_id} failed"
        error -> "task #{task_id} failed: #{error}"
      end

    {:error, %Error{message: message, reason: :failed, task_id: task_id, status: status}}
  end

  defp check_failed(_task_id, status), do: {:ok, status}

  defp await_segments(task_id, status, deadline, poll_interval, request_opts, opts) do
    case Keyword.get(opts, :data_source) || status["dataSource"] do
      nil ->
        {:error,
         %Error{
           message: "can't wait for segments of task #{task_id}: it has no data source",
           task_id: task_id,
           status: status
         }}

      data_source ->
        interval = Keyword.get(opts, :segments_interval, @all_time)

        check = fn -> check_segments(data_source, interval, request_opts) end

        case poll(deadline, poll_interval, check) do
          {:ok, _} ->
            {:ok, status}

          {:error, error} ->
            {:error, error}

          nil ->
            {:error, timeout_error(task_id, status, "segments of #{data_source} to load")}
        end
    end
  end

  defp check_segments(data_source, interval, request_opts) do
    request =
      Druid.Client.DataSource.load_status(data_source,
        simple: true,
        force_metadata_refresh: true,
        interval: interval
      )

    case Druid.Client.request(request, request_opts) do
      {:ok, %{^data_source => left}} when left > 0 -> :wait
      # Druid answers with text (or nothing) when there are no used segments
      {:ok, _loaded} -> {:done, :loaded}
      {:error, error} -> {:error, error}
    end
  end

  defp timeout_error(task_id, status, what) do
    %Error{
      message: "timed out waiting for #{what}",
      reason: :timeout,
      task_id: task_id,
      status: status
    }
  end

  # Calls `check` until it returns `{:done, value}` or `{:error, error}`.
  # Returns `{:ok, value}`, `{:error, error}`, or `nil` past the deadline.
  defp poll(deadline, interval, check) do
    case check.() do
      {:done, value} ->
        {:ok, value}

      {:error, error} ->
        {:error, error}

      :wait ->
        case remaining(deadline) do
          0 ->
            nil

          remaining ->
            Process.sleep(min(interval, remaining))
            poll(deadline, interval, check)
        end
    end
  end

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
