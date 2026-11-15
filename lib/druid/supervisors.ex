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

  Compaction configs, retention rules and lookups are managed the same way,
  from their own template directories. See `Druid.Compaction`,
  `Druid.Retention` and `Druid.Lookups`.
  """

  alias Druid.SpecTemplates

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
    defexception [:message]
  end

  @default_path "priv/druid/supervisors"

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
