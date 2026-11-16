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

  In a release, call `run/3` from your release module:

      defmodule MyApp.Release do
        def backfill_page_views(interval) do
          Application.load(:my_app)
          {:ok, _} = Application.ensure_all_started(:req)

          Druid.Tasks.run(MyApp.DruidRepo, "backfill_page_views",
            assigns: %{interval: interval},
            wait_for_segments: true
          )
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
    """
    @type t :: %__MODULE__{
            name: String.t(),
            path: Path.t(),
            data_source: String.t() | nil,
            spec: map()
          }
    defstruct [:name, :path, :data_source, :spec]
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

    deadline =
      case Keyword.get(opts, :timeout, :infinity) do
        :infinity -> :infinity
        timeout -> System.monotonic_time(:millisecond) + timeout
      end

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
