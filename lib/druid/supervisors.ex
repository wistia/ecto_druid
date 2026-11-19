defmodule Druid.Supervisors do
  @moduledoc """
  Manages Druid supervisor specs (Kafka ingestion, automatic compaction, and
  so on) as EEx templates in your application, with the values that change
  between environments supplied from config.

  ## Templates

  Each `*.json.eex` file in the templates directory (default
  `priv/druid/supervisors`, searched recursively) is one supervisor spec. A
  template is the JSON you would submit to Druid, with EEx for the parts
  that vary:

      {
        "type": "kafka",
        "spec": {
          "ioConfig": {
            "topic": "page_views",
            "consumerProperties": <%= json @kafka.consumer_properties %>,
            "inputFormat": {
              "type": "avro_stream",
              "avroBytesDecoder": {"type": "schema_registry", "url": <%= json @schema_registry_url %>}
            },
            "taskCount": <%= @task_count %>
          },
          "tuningConfig": {
            "type": "kafka",
            "indexSpec": <%= partial "index_spec" %>
          },
          "dataSchema": {
            "dataSource": "page_views_hourly",
            ...
          }
        }
      }

  Plain `*.json` files are also picked up, for specs that don't vary.

  Inside templates:

    * `@name` reads an assign. A missing assign raises rather than rendering
      nothing.
    * `json/1` encodes a value as JSON. Use it for strings, maps and lists.
    * `partial/1,2` renders a shared fragment. Partials are files whose name
      starts with `_`, for example `_index_spec.json.eex`. They aren't specs
      themselves. See `Druid.Supervisors.Template.Helpers`.
    * `@spec_name` is the template's path relative to the templates directory,
      without the extension.

  Compaction supervisors are supervisor specs too, so they can go in the same
  directory:

      {"type": "autocompact", "spec": {"dataSource": "wikipedia", "skipOffsetFromLatest": "P1D"}}

  `Druid.Compaction` manages the same compaction configs through Druid's
  compaction API instead, which also works when the cluster runs compaction
  on the Coordinator. Use one or the other for each data source.

  ## Generating the data schema

  If the datasource is described by a schema that uses `Ecto.Druid.Schema`,
  templates can generate the timestamp, dimensions and metrics from it
  instead of listing them by hand:

      "dataSchema": <%= data_schema MyApp.PageViewsHourly, segment_granularity: "DAY", filter: @filter %>

  In a compaction spec, use the combining metrics, which re-aggregate the
  stored columns:

      "dimensionsSpec": <%= dimensions_spec MyApp.PageViewsHourly %>,
      "metricsSpec": <%= metrics_spec MyApp.PageViewsHourly, combining: true %>

  ## Configuration

  Configure supervisors under the `:supervisors` key of your Druid repo's
  config. Values that vary by environment come from config, so you can set
  them from environment variables in `config/runtime.exs` the same way you
  configure the repo itself:

      app_env = System.get_env("APP_ENV", "dev")

      config :my_app, MyApp.DruidRepo,
        host: System.get_env("DRUID_BROKER_HOST", "localhost"),
        port: 8082,
        supervisors: [
          # The supervisor API lives on the Router/Overlord, not the Broker.
          # These default to the repo's :host, :port and :scheme.
          host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
          port: 8888,
          assigns: %{
            kafka: %{
              consumer_properties: %{
                "bootstrap.servers" => System.get_env("KAFKA_BROKERS", "localhost:9092")
              }
            },
            schema_registry_url: System.get_env("SCHEMA_REGISTRY_URL", "http://localhost:8081"),
            task_count: 1
          },
          # Per-spec assigns, keyed by spec name, deep-merged over :assigns.
          specs: %{
            "page_views_hourly" => %{
              task_count: if(app_env == "prod", do: 4, else: 1)
            }
          }
        ]

  The supported options are:

    * `:path` - The templates directory. A relative path is resolved against
      the repo's OTP app directory (like `priv/repo/migrations`). Defaults to
      `"priv/druid/supervisors"`.
    * `:assigns` - Assigns available to every template.
    * `:specs` - A map of spec name to assigns for that spec only.
    * `:host`, `:port`, `:scheme` - Where to send supervisor API requests.
      Default to the repo's values.
    * `:receive_timeout` - How long to wait for each response from Druid,
      in milliseconds. Defaults to `15_000`.
    * `:retry`, `:max_retries`, `:retry_delay`, `:retry_log_level` - How
      failed requests are retried, as in `Druid.Client`'s options.

  Every option can also be given to `render/2` and `sync/2` directly, which
  take precedence over config.

  ## Applying specs

  In development, use the Mix tasks:

      mix druid.supervisors.render          # print the rendered specs
      mix druid.supervisors.sync --dry-run  # show what would be submitted
      mix druid.supervisors.sync            # submit them

  Mix isn't available in a release, so call `sync/2` from your release module
  instead, for example from a deploy job the way you would run migrations:

      defmodule MyApp.Release do
        def sync_druid_supervisors do
          Application.load(:my_app)
          {:ok, _} = Application.ensure_all_started(:req)
          Druid.Supervisors.sync(MyApp.DruidRepo)
        end
      end

      bin/my_app eval "MyApp.Release.sync_druid_supervisors()"

  Druid compares each submitted spec with the running one and only restarts a
  supervisor when its spec changed, so syncing unchanged specs is safe.

  Compaction configs, retention rules, lookups and batch ingestion tasks are
  managed the same way, from their own template directories. See
  `Druid.Compaction`, `Druid.Retention`, `Druid.Lookups` and `Druid.Tasks`.

  ## Waiting for streaming ingestion

  Two functions wait on a streaming supervisor, which helps in tests that
  write to a stream and query what Druid made of it:

    * `await_running/3` waits until the supervisor's tasks are reading the
      stream. A spec with `"useEarliestOffset": false` starts from the end of
      the stream, so messages written before then are never ingested.
    * `handoff/3` makes the tasks publish their segments now rather than at
      the end of their `taskDuration`, and waits for them to finish, so the
      rows can be queried from Historicals.

  For example:

      [{:created, _}] = Druid.Supervisors.sync(MyApp.DruidRepo, only: ["page_views"])
      {:ok, _} = Druid.Supervisors.await_running(MyApp.DruidRepo, "page_views", timeout: 120_000)

      produce_page_views()
      # ... query the rows the tasks hold in memory ...

      {:ok, _} =
        Druid.Supervisors.handoff(MyApp.DruidRepo, "page_views",
          wait_for_segments: true,
          timeout: 300_000
        )

      # ... query them again, now from Historicals ...
  """

  alias Druid.{Poll, SpecTemplates}

  defmodule Spec do
    @moduledoc """
    A rendered supervisor spec.

      * `:name` - The template's path relative to the templates directory,
        without its extension.
      * `:path` - The template's absolute path.
      * `:id` - The supervisor ID Druid will use.
      * `:spec` - The rendered spec, decoded from JSON.
    """
    @type t :: %__MODULE__{name: String.t(), path: Path.t(), id: String.t(), spec: map()}
    defstruct [:name, :path, :id, :spec]
  end

  defmodule Error do
    @moduledoc """
    Raised when a supervisor template can't be rendered, and returned when
    waiting on a supervisor fails.

      * `:reason` - Why waiting failed: `:timeout`, `:suspended`,
        `:unhealthy` or `:no_active_tasks`. `nil` for a template error.
      * `:supervisor_id` - The supervisor's ID, when waiting on one.
      * `:status` - The supervisor's last status report (its `"payload"`),
        when there is one.
    """
    @type t :: %__MODULE__{
            message: String.t(),
            reason: :timeout | :suspended | :unhealthy | :no_active_tasks | nil,
            supervisor_id: String.t() | nil,
            status: map() | nil
          }
    defexception [:message, :reason, :supervisor_id, :status]
  end

  @default_path "priv/druid/supervisors"
  @default_poll_interval 2_000
  @unhealthy_states ["UNHEALTHY_SUPERVISOR", "UNHEALTHY_TASKS"]

  @doc """
  Renders every supervisor spec template for `repo`.

  Raises if a template fails to render, isn't valid JSON, has no supervisor
  ID, or shares an ID with another template.

  ## Options

    * `:only` - A list of spec names to render. Defaults to all of them.
    * any option from the "Configuration" section of the module docs.
  """
  @spec render(Ecto.Repo.t(), Keyword.t()) :: [Spec.t()]
  def render(repo, opts \\ []) do
    config = SpecTemplates.config(repo, :supervisors, opts)
    root = SpecTemplates.root!(repo, config, @default_path, Error, "supervisor")

    root
    |> SpecTemplates.discover()
    |> SpecTemplates.filter_only(Keyword.get(opts, :only), Error, "supervisor")
    |> Enum.map(&render_spec(&1, root, config))
    |> SpecTemplates.check_unique!(
      & &1.id,
      & &1.name,
      Error,
      "multiple templates have the same supervisor ID"
    )
  end

  @doc """
  Renders the supervisor specs for `repo` and submits them to Druid.

  Returns one result per spec, plus one per pruned supervisor:

    * `{:created, spec}` - No supervisor with this ID existed.
    * `{:updated, spec}` - The spec changed and Druid restarted the supervisor.
    * `{:unchanged, spec}` - The spec matched the running one.
    * `{:restarted, spec}` - The spec matched, but `restart: true` restarted it.
    * `{:would_create, spec}` / `{:would_update, spec}` - In dry-run mode.
    * `{:terminated, id}` / `{:would_terminate, id}` - With `prune: true`.
    * `{:error, spec_or_id, exception}` - The request failed. Other specs are
      still submitted.

  ## Options

    * `:dry_run` - Render the specs and compare their IDs with the running
      supervisors without submitting anything. Druid has no dry-run for
      supervisor specs, so this can't tell whether an existing spec changed.
    * `:prune` - Terminate running supervisors that have no template. Can't
      be combined with `:only`. Defaults to `false`.
    * `:restart` - Restart every submitted supervisor, even unchanged ones.
      Defaults to `false`.
    * `:only` and the configuration options accepted by `render/2`.
  """
  @spec sync(Ecto.Repo.t(), Keyword.t()) :: [tuple()]
  def sync(repo, opts \\ []) do
    prune? = Keyword.get(opts, :prune, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    restart? = Keyword.get(opts, :restart, false)

    if prune? and Keyword.has_key?(opts, :only) do
      raise ArgumentError, ":prune can't be combined with :only"
    end

    specs = render(repo, opts)

    request_opts =
      SpecTemplates.request_opts(repo, SpecTemplates.config(repo, :supervisors, opts))

    existing =
      Druid.Client.Supervisor.list()
      |> Druid.Client.request!(request_opts)
      |> MapSet.new()

    submitted =
      Enum.map(specs, fn spec ->
        submit(spec, existing, dry_run?, restart?, request_opts)
      end)

    pruned =
      if prune? do
        defined = MapSet.new(specs, & &1.id)

        existing
        |> Enum.reject(&MapSet.member?(defined, &1))
        |> Enum.sort()
        |> Enum.map(&terminate(&1, dry_run?, request_opts))
      else
        []
      end

    submitted ++ pruned
  end

  defp submit(spec, existing, true = _dry_run?, _restart?, _request_opts) do
    if MapSet.member?(existing, spec.id), do: {:would_update, spec}, else: {:would_create, spec}
  end

  defp submit(spec, existing, false = _dry_run?, restart?, request_opts) do
    response =
      Druid.Client.Supervisor.submit(spec.spec, skip_restart_if_unmodified: not restart?)
      |> Druid.Client.request!(request_opts)

    cond do
      not MapSet.member?(existing, spec.id) -> {:created, spec}
      response["modified"] != false -> {:updated, spec}
      response["restarted"] == true -> {:restarted, spec}
      true -> {:unchanged, spec}
    end
  rescue
    error -> {:error, spec, error}
  end

  defp terminate(id, true = _dry_run?, _request_opts), do: {:would_terminate, id}

  defp terminate(id, false = _dry_run?, request_opts) do
    Druid.Client.Supervisor.terminate(id) |> Druid.Client.request!(request_opts)
    {:terminated, id}
  rescue
    error -> {:error, id, error}
  end

  @doc """
  Waits until a streaming supervisor's tasks are reading the stream.

  Returns `{:ok, status}`, where `status` is the supervisor's status report
  (the `"payload"` of `Druid.Client.Supervisor.status/1`), once the
  supervisor is `RUNNING` and each of its active tasks has reported the
  offsets it has read up to. Messages written to the stream from then on are
  ingested, even by a spec with `"useEarliestOffset": false`.

  Returns `{:error, %Druid.Supervisors.Error{}}` when:

    * the supervisor is suspended (`reason: :suspended`),
    * it is `UNHEALTHY_SUPERVISOR` or `UNHEALTHY_TASKS` (`reason:
      :unhealthy`), with its recent errors in the message, or
    * it isn't running by the timeout (`reason: :timeout`).

  Request errors are returned as `{:error, exception}`, including the 404
  for a supervisor that doesn't exist.

  Druid only reports a supervisor unhealthy after several failures in a row
  (`druid.supervisor.unhealthinessThreshold` and
  `taskUnhealthinessThreshold`, 3 by default), so a supervisor that can't
  reach its stream can take a few minutes to fail rather than time out.

  ## Options

    * `:timeout` - How long to wait in milliseconds. Defaults to `:infinity`.
    * `:poll_interval` - How often to check, in milliseconds. Defaults to
      `#{@default_poll_interval}`.
    * `:host`, `:port`, `:scheme` - As in the "Configuration" section of the
      module docs.
  """
  @spec await_running(Ecto.Repo.t(), String.t(), Keyword.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def await_running(repo, id, opts \\ []) do
    request_opts = request_opts(repo, opts)
    deadline = Poll.deadline(Keyword.get(opts, :timeout, :infinity))
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)

    case Poll.poll(deadline, poll_interval, fn -> check_running(id, request_opts) end) do
      {:timeout, status} ->
        state = status && status["detailedState"]

        {:error,
         %Error{
           message:
             "timed out waiting for supervisor #{id} to start reading" <>
               if(state, do: " (it is #{state})", else: ""),
           reason: :timeout,
           supervisor_id: id,
           status: status
         }}

      result ->
        result
    end
  end

  defp check_running(id, request_opts) do
    with {:ok, status} <- fetch_status(id, request_opts) do
      cond do
        status["suspended"] == true ->
          {:error,
           %Error{
             message: "supervisor #{id} is suspended",
             reason: :suspended,
             supervisor_id: id,
             status: status
           }}

        status["state"] in @unhealthy_states ->
          {:error,
           %Error{
             message: "supervisor #{id} is #{status["detailedState"]}" <> recent_errors(status),
             reason: :unhealthy,
             supervisor_id: id,
             status: status
           }}

        reading?(status) ->
          {:done, status}

        true ->
          {:wait, status}
      end
    end
  end

  # A task's currentOffsets stay empty until it has started and read from
  # the stream.
  defp reading?(%{"state" => "RUNNING", "activeTasks" => [_ | _] = tasks}) do
    Enum.all?(tasks, &match?(%{"currentOffsets" => offsets} when map_size(offsets) > 0, &1))
  end

  defp reading?(_status), do: false

  defp recent_errors(%{"recentErrors" => [_ | _] = errors}) do
    messages =
      errors
      |> Enum.take(-3)
      |> Enum.map(&(&1["exceptionClass"] || &1["message"] || inspect(&1)))
      |> Enum.uniq()

    ": " <> Enum.join(messages, "; ")
  end

  defp recent_errors(_status), do: ""

  @doc """
  Makes a streaming supervisor's tasks publish their segments now, and waits
  for those tasks to finish.

  Druid normally publishes a task's segments at the end of its
  `taskDuration`. This asks the supervisor to stop its active tasks early
  (Druid's `taskGroups/handoff` API); they publish what they hold and new
  tasks carry on reading. Kafka and Kinesis tasks wait for their segments
  to be loaded by Historicals before finishing, up to the tuning config's
  `handoffConditionTimeout` (15 minutes by default).

  Returns `{:ok, statuses}`, one task status per task that was active, once
  they have all succeeded. Returns `{:error, %Druid.Tasks.Error{}}` when one
  of them fails or doesn't finish in time,
  `{:error, %Druid.Supervisors.Error{reason: :no_active_tasks}}` when the
  supervisor has no active tasks to stop, and `{:error, exception}` when a
  request fails.

  ## Options

    * `:task_groups` - The task group IDs to hand off. Defaults to all of
      them, `0` up to the spec's `taskCount`.
    * `:wait` - When `false`, return `{:ok, task_ids}` as soon as Druid has
      accepted the request, without waiting. Defaults to `true`.
    * `:wait_for_segments` - When `true`, also wait until Historicals have
      loaded the data source's segments, as in `Druid.Tasks.await/3`.
      Defaults to `false`.
    * `:segments_interval` - Only wait for segments in this interval.
      Defaults to all of them.
    * `:timeout` - How long to wait in milliseconds, for all the tasks
      together. Defaults to `:infinity`.
    * `:poll_interval` - How often to check, in milliseconds. Defaults to
      `#{@default_poll_interval}`.
    * `:host`, `:port`, `:scheme` - As in the "Configuration" section of the
      module docs.

  Waiting runs `Druid.Tasks.await/3` for each task, so it emits its
  `[:druid, :task, :await]` telemetry spans.
  """
  @spec handoff(Ecto.Repo.t(), String.t(), Keyword.t()) ::
          {:ok, [map()] | [String.t()]} | {:error, Exception.t()}
  def handoff(repo, id, opts \\ []) do
    request_opts = request_opts(repo, opts)
    deadline = Poll.deadline(Keyword.get(opts, :timeout, :infinity))

    with {:ok, status} <- fetch_status(id, request_opts),
         {:ok, task_ids} <- active_task_ids(id, status),
         {:ok, groups} <- task_groups(id, request_opts, opts),
         {:ok, _} <-
           Druid.Client.Supervisor.handoff(id, groups) |> Druid.Client.request(request_opts) do
      if Keyword.get(opts, :wait, true) do
        await_tasks(repo, task_ids, deadline, request_opts, opts)
      else
        {:ok, task_ids}
      end
    end
  end

  defp active_task_ids(id, status) do
    case status["activeTasks"] do
      [_ | _] = tasks ->
        {:ok, Enum.map(tasks, & &1["id"])}

      _ ->
        {:error,
         %Error{
           message: "supervisor #{id} has no active tasks to hand off",
           reason: :no_active_tasks,
           supervisor_id: id,
           status: status
         }}
    end
  end

  # Kafka and Kinesis assign each partition to task group
  # `partition rem taskCount`, so the groups are 0 up to taskCount. Druid
  # ignores groups that aren't reading.
  defp task_groups(id, request_opts, opts) do
    case Keyword.fetch(opts, :task_groups) do
      {:ok, groups} ->
        {:ok, groups}

      :error ->
        with {:ok, spec} <- Druid.Client.Supervisor.get(id) |> Druid.Client.request(request_opts) do
          count = get_in(spec, ["spec", "ioConfig", "taskCount"]) || 1
          {:ok, Enum.to_list(0..(count - 1)//1)}
        end
    end
  end

  defp await_tasks(repo, task_ids, deadline, request_opts, opts) do
    await_opts =
      opts
      |> Keyword.take([:poll_interval, :wait_for_segments, :segments_interval])
      |> Keyword.merge(Keyword.delete(request_opts, :telemetry_metadata))

    Enum.reduce_while(task_ids, {:ok, []}, fn task_id, {:ok, statuses} ->
      timeout = Poll.remaining(deadline)

      case Druid.Tasks.await(repo, task_id, [timeout: timeout] ++ await_opts) do
        {:ok, status} -> {:cont, {:ok, [status | statuses]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, statuses} -> {:ok, Enum.reverse(statuses)}
      error -> error
    end
  end

  defp fetch_status(id, request_opts) do
    case Druid.Client.Supervisor.status(id) |> Druid.Client.request(request_opts) do
      {:ok, %{"payload" => %{} = status}} ->
        {:ok, status}

      {:ok, body} ->
        {:error,
         %Error{
           message: "unexpected status for supervisor #{id}: #{inspect(body)}",
           supervisor_id: id
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp request_opts(repo, opts),
    do: SpecTemplates.request_opts(repo, SpecTemplates.config(repo, :supervisors, opts))

  @doc """
  Returns the supervisor ID Druid assigns to a spec.

  This is the spec's `"id"` if it has one. Otherwise it's the data source for
  streaming specs, and `"autocompact__"` followed by the data source for
  compaction specs.
  """
  @spec supervisor_id(map()) :: String.t() | nil
  def supervisor_id(%{"id" => id}) when is_binary(id), do: id

  def supervisor_id(%{"type" => "autocompact", "spec" => %{"dataSource" => ds}})
      when is_binary(ds),
      do: "autocompact__" <> ds

  def supervisor_id(%{"spec" => %{"dataSchema" => %{"dataSource" => ds}}}) when is_binary(ds),
    do: ds

  def supervisor_id(%{"dataSchema" => %{"dataSource" => ds}}) when is_binary(ds), do: ds
  def supervisor_id(_spec), do: nil

  defp render_spec({name, path}, root, config) do
    spec =
      case SpecTemplates.render!(name, path, root, config, Error) do
        %{} = spec -> spec
        _ -> raise Error, "#{name} must render a JSON object"
      end

    id =
      supervisor_id(spec) ||
        raise Error,
              "#{name} has no supervisor ID. Set \"id\", spec.dataSchema.dataSource, " <>
                "or spec.dataSource for autocompact"

    %Spec{name: name, path: path, id: id, spec: spec}
  end
end
