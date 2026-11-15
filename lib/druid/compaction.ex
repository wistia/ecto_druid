defmodule Druid.Compaction do
  @moduledoc """
  Manages Druid automatic compaction configs as EEx templates in your
  application, with the values that change between environments supplied
  from config.

  ## Templates

  Each `*.json.eex` file in the templates directory (default
  `priv/druid/compaction`, searched recursively) is the compaction config of
  one data source, named after the file. It renders the JSON you would
  submit to Druid, without `"dataSource"` unless you want to set it
  explicitly:

      {
        "skipOffsetFromLatest": "P1D",
        "granularitySpec": {"segmentGranularity": "DAY"},
        "dimensionsSpec": <%= dimensions_spec MyApp.PageViewsHourly %>,
        "metricsSpec": <%= metrics_spec MyApp.PageViewsHourly, combining: true %>,
        "tuningConfig": {
          "partitionsSpec": {"type": "dynamic", "maxRowsPerSegment": <%= @target_rows %>},
          "maxNumConcurrentSubTasks": <%= @max_subtasks %>
        }
      }

  Templates work the same way as supervisor spec templates, including the
  schema helpers. See `Druid.Supervisors` for details.

  ## Supervisors or the Coordinator

  Druid runs automatic compaction either as compaction supervisors or as a
  Coordinator duty, depending on the cluster's `useSupervisors` setting
  (supervisors are the default in Druid 38). The compaction API used here
  works in both modes. With supervisors, a data source's compaction config
  is its `autocompact__<dataSource>` supervisor.

  That means you can also define compaction as `"autocompact"` supervisor
  specs with `Druid.Supervisors`. Pick one for each data source. In
  particular, `prune: true` in either module removes the compaction that the
  other defines.

  ## Configuration

  Configure compaction under the `:compaction` key of your Druid repo's
  config:

      config :my_app, MyApp.DruidRepo,
        compaction: [
          # The compaction API lives on the Router/Overlord, not the Broker.
          host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
          port: 8888,
          assigns: %{target_rows: 5_000_000, max_subtasks: 1},
          # Per-template assigns, keyed by template name.
          specs: %{"page_views_hourly" => %{max_subtasks: 3}}
        ]

  The supported options are:

    * `:path` - The templates directory. A relative path is resolved against
      the repo's OTP app directory. Defaults to `"priv/druid/compaction"`.
    * `:assigns` - Assigns available to every template.
    * `:specs` - A map of template name to assigns for that template only.
    * `:author`, `:comment` - Sent as the audit author and comment for each
      change. Default to `"ecto_druid"` and a comment naming the template.
      With compaction supervisors, Druid 38 keeps each config in its
      history but doesn't record these.
    * `:host`, `:port`, `:scheme` - Where to send compaction API requests.
      Default to the repo's values.

  Every option can also be given to `render/2` and `sync/2` directly, which
  take precedence over config.

  ## Applying configs

      mix druid.compaction.render          # print the rendered configs
      mix druid.compaction.sync --dry-run  # show what would change
      mix druid.compaction.sync            # submit them

  In a release, call `sync/2` instead, the same way as
  `Druid.Supervisors.sync/2`.

  ## How changes are detected

  Druid stores compaction configs with every default filled in: string
  dimensions become objects, sketches get their default parameters, and so
  on. So `sync/2` treats a config as unchanged when every value in the
  template matches Druid's, ignoring settings the template leaves out.

  The catch is that removing a setting from a template isn't seen as a
  change, because Druid's copy still has the old value. Sync with
  `force: true` (`--force`) after removing one.
  """

  alias Druid.SpecTemplates

  defmodule Config do
    @moduledoc """
    A rendered compaction config.

      * `:name` - The template's path relative to the templates directory,
        without its extension.
      * `:path` - The template's absolute path.
      * `:data_source` - The data source the config applies to.
      * `:config` - The rendered config, decoded from JSON, with
        `"dataSource"` set.
    """
    @type t :: %__MODULE__{
            name: String.t(),
            path: Path.t(),
            data_source: String.t(),
            config: map()
          }
    defstruct [:name, :path, :data_source, :config]
  end

  defmodule Error do
    defexception [:message]
  end

  @default_path "priv/druid/compaction"

  @doc """
  Renders every compaction config template for `repo`.

  Raises if a template fails to render, doesn't render a JSON object, or
  configures the same data source as another template.

  ## Options

    * `:only` - A list of template names to render. Defaults to all of them.
    * any option from the "Configuration" section of the module docs.
  """
  @spec render(Ecto.Repo.t(), Keyword.t()) :: [Config.t()]
  def render(repo, opts \\ []) do
    config = SpecTemplates.config(repo, :compaction, opts)
    root = SpecTemplates.root!(repo, config, @default_path, Error, "compaction")

    root
    |> SpecTemplates.discover()
    |> SpecTemplates.filter_only(Keyword.get(opts, :only), Error, "compaction")
    |> Enum.map(&render_config(&1, root, config))
    |> SpecTemplates.check_unique!(
      & &1.data_source,
      & &1.name,
      Error,
      "multiple templates configure compaction for the same data source"
    )
  end

  @doc """
  Renders the compaction configs for `repo` and submits the ones that
  changed.

  Returns one result per template, plus one per pruned config:

    * `{:created, config}` - The data source had no compaction config.
    * `{:updated, config}` - The config changed.
    * `{:unchanged, config}` - The config matched Druid's.
    * `{:would_create, config}` / `{:would_update, config}` - In dry-run
      mode.
    * `{:deleted, data_source}` / `{:would_delete, data_source}` - With
      `prune: true`.
    * `{:error, config_or_data_source, exception}` - The request failed.
      Other configs are still submitted.

  ## Options

    * `:dry_run` - Compare the configs with Druid's without submitting
      anything.
    * `:force` - Submit every config, even ones that look unchanged.
    * `:prune` - Delete the compaction configs of data sources that have no
      template, which stops compacting them. Can't be combined with `:only`.
      Defaults to `false`.
    * `:only` and the configuration options accepted by `render/2`.
  """
  @spec sync(Ecto.Repo.t(), Keyword.t()) :: [tuple()]
  def sync(repo, opts \\ []) do
    prune? = Keyword.get(opts, :prune, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    force? = Keyword.get(opts, :force, false)

    if prune? and Keyword.has_key?(opts, :only) do
      raise ArgumentError, ":prune can't be combined with :only"
    end

    configs = render(repo, opts)
    config = SpecTemplates.config(repo, :compaction, opts)
    request_opts = SpecTemplates.request_opts(repo, config)

    current =
      Druid.Client.Compaction.all()
      |> Druid.Client.request!(request_opts)
      |> Map.get("compactionConfigs", [])
      |> Map.new(&{&1["dataSource"], &1})

    submitted =
      Enum.map(configs, fn compaction ->
        existing = Map.get(current, compaction.data_source)
        submit(compaction, existing, dry_run?, force?, config, request_opts)
      end)

    pruned =
      if prune? do
        defined = MapSet.new(configs, & &1.data_source)

        current
        |> Map.keys()
        |> Enum.reject(&MapSet.member?(defined, &1))
        |> Enum.sort()
        |> Enum.map(&delete(&1, dry_run?, config, request_opts))
      else
        []
      end

    submitted ++ pruned
  end

  defp submit(compaction, existing, dry_run?, force?, config, request_opts) do
    cond do
      existing && not force? && matches?(compaction.config, existing) ->
        {:unchanged, compaction}

      dry_run? ->
        if existing, do: {:would_update, compaction}, else: {:would_create, compaction}

      true ->
        Druid.Client.Compaction.set(compaction.config, audit(config, compaction.name))
        |> Druid.Client.request!(request_opts)

        if existing, do: {:updated, compaction}, else: {:created, compaction}
    end
  rescue
    error -> {:error, compaction, error}
  end

  defp delete(data_source, true = _dry_run?, _config, _request_opts),
    do: {:would_delete, data_source}

  defp delete(data_source, false = _dry_run?, config, request_opts) do
    Druid.Client.Compaction.delete(data_source, audit(config, nil))
    |> Druid.Client.request!(request_opts)

    {:deleted, data_source}
  rescue
    error -> {:error, data_source, error}
  end

  defp audit(config, name) do
    comment =
      if name,
        do: "Synced from compaction template #{name}",
        else: "Removed by Druid.Compaction: no template"

    [
      author: Keyword.get(config, :author, "ecto_druid"),
      comment: Keyword.get(config, :comment, comment)
    ]
  end

  @doc """
  Returns whether every value in the `rendered` config matches the `stored`
  one Druid returns. Settings only in `stored` are ignored, a `null` in
  `rendered` matches a missing or `null` setting, and a string dimension
  matches the string dimension object Druid expands it to.
  """
  @spec matches?(term(), term()) :: boolean()
  def matches?(rendered, stored) when is_map(rendered) and is_map(stored) do
    Enum.all?(rendered, fn {key, value} ->
      case Map.fetch(stored, key) do
        {:ok, stored_value} -> matches?(value, stored_value)
        :error -> is_nil(value)
      end
    end)
  end

  def matches?(rendered, stored) when is_list(rendered) and is_list(stored) do
    length(rendered) == length(stored) and
      rendered |> Enum.zip(stored) |> Enum.all?(fn {r, s} -> matches?(r, s) end)
  end

  def matches?(name, %{"type" => "string", "name" => name}) when is_binary(name), do: true
  def matches?(rendered, stored), do: rendered == stored

  defp render_config({name, path}, root, config) do
    case SpecTemplates.render!(name, path, root, config, Error) do
      %{"dataSource" => ds} = compaction when is_binary(ds) ->
        %Config{name: name, path: path, data_source: ds, config: compaction}

      %{"dataSource" => _} ->
        raise Error, "#{name}: \"dataSource\" must be a string"

      %{} = compaction ->
        ds = Path.basename(name)

        %Config{
          name: name,
          path: path,
          data_source: ds,
          config: Map.put(compaction, "dataSource", ds)
        }

      _ ->
        raise Error, "#{name} must render a JSON object"
    end
  end
end
