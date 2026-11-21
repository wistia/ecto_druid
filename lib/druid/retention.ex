defmodule Druid.Retention do
  @moduledoc """
  Manages Druid retention rules as EEx templates in your application, with
  the values that change between environments supplied from config.

  ## Templates

  Each `*.json.eex` file in the templates directory (default
  `priv/druid/retention`, searched recursively) holds the rules of one data
  source, named after the file. It renders the JSON list of rules you would
  submit to Druid:

      [
        {
          "type": "loadByPeriod",
          "period": "P2Y",
          "tieredReplicants": {<%= json @historical_tier %>: <%= @replicas %>}
        },
        {"type": "dropForever"}
      ]

  A template can name its data source instead, by rendering an object with
  `"dataSource"` and `"rules"`. Use this for the cluster-wide default rules,
  which Druid keeps under the data source `"_default"` (a file can't be named
  `_default`, since files starting with `_` are partials):

      {"dataSource": "_default", "rules": [{"type": "loadForever"}]}

  Templates work the same way as supervisor spec templates: `@name` reads an
  assign (and raises if it's missing), `json/1` encodes a value, and
  `partial/1,2` renders a shared `_name.json.eex` fragment. See
  `Druid.Supervisors` for details.

  ## Configuration

  Configure retention rules under the `:retention` key of your Druid repo's
  config:

      config :my_app, MyApp.DruidRepo,
        retention: [
          # The rules API lives on the Router/Coordinator, not the Broker.
          host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
          port: 8888,
          assigns: %{
            historical_tier: System.get_env("DRUID_HISTORICAL_TIER", "_default_tier"),
            replicas: 2
          },
          # Per-template assigns, keyed by template name.
          specs: %{"page_views_hourly" => %{replicas: 1}}
        ]

  The supported options are:

    * `:path` - The templates directory. A relative path is resolved against
      the repo's OTP app directory. Defaults to `"priv/druid/retention"`.
    * `:assigns` - Assigns available to every template.
    * `:specs` - A map of template name to assigns for that template only.
    * `:tiers` - The tiers rules may load segments onto. Defaults to the
      tiers that currently have Historicals. See "Tier check" below.
    * `:author`, `:comment` - Recorded in Druid's audit history for each
      change. Default to `"ecto_druid"` and a comment naming the template.
    * `:host`, `:port`, `:scheme` - Where to send rules API requests. Default
      to the repo's values.
    * `:receive_timeout` - How long to wait for each response from Druid,
      in milliseconds. Defaults to `15_000`.
    * `:retry`, `:max_retries`, `:retry_delay`, `:retry_log_level` - How
      failed requests are retried, as in `Druid.Client`'s options.

  Every option can also be given to `render/2` and `sync/2` directly, which
  take precedence over config.

  ## Tier check

  Druid accepts rules that load segments onto a tier with no Historicals,
  which unloads the data source from every other tier. To catch a mistyped
  tier name, `sync/2` refuses to submit rules that name a tier outside
  `:tiers`. A load rule without `"tieredReplicants"` uses `_default_tier`, so
  it's checked too. Set `tiers: false` to skip the check.

  ## Applying rules

      mix druid.retention.render          # print the rendered rules
      mix druid.retention.sync --dry-run  # show what would change
      mix druid.retention.sync            # submit them

  In a release, call `sync/2` instead, the same way as
  `Druid.Supervisors.sync/2`.

  Rules are compared with the ones Druid has, after filling in Druid's
  defaults, so only data sources whose rules changed are submitted.
  """

  alias Druid.SpecTemplates

  defmodule Rules do
    @moduledoc """
    The rendered retention rules of one data source.

      * `:name` - The template's path relative to the templates directory,
        without its extension.
      * `:path` - The template's absolute path.
      * `:data_source` - The data source the rules apply to.
      * `:rules` - The rendered rules, decoded from JSON.
    """
    @type t :: %__MODULE__{
            name: String.t(),
            path: Path.t(),
            data_source: String.t(),
            rules: [map()]
          }
    defstruct [:name, :path, :data_source, :rules]
  end

  defmodule Error do
    defexception [:message]
  end

  @default_path "priv/druid/retention"
  @default_tier "_default_tier"
  @load_rules ~w(loadForever loadByPeriod loadByInterval)
  @future_rules ~w(loadByPeriod dropByPeriod broadcastByPeriod)

  @doc """
  Renders every retention rules template for `repo`.

  Raises if a template fails to render, doesn't render a list of rules, or
  names the same data source as another template.

  ## Options

    * `:only` - A list of template names to render. Defaults to all of them.
    * any option from the "Configuration" section of the module docs.
  """
  @spec render(Ecto.Repo.t(), Keyword.t()) :: [Rules.t()]
  def render(repo, opts \\ []) do
    config = SpecTemplates.config(repo, :retention, opts)
    root = SpecTemplates.root!(repo, config, @default_path, Error, "retention")

    root
    |> SpecTemplates.discover()
    |> SpecTemplates.filter_only(Keyword.get(opts, :only), Error, "retention")
    |> Enum.map(&render_rules(&1, root, config))
    |> SpecTemplates.check_unique!(
      & &1.data_source,
      & &1.name,
      Error,
      "multiple templates have rules for the same data source"
    )
  end

  @doc """
  Renders the retention rules for `repo` and submits the ones that changed.

  Returns one result per template, plus one per pruned data source:

    * `{:created, rules}` - The data source had no rules.
    * `{:updated, rules}` - The rules changed.
    * `{:unchanged, rules}` - The rules matched Druid's.
    * `{:would_create, rules}` / `{:would_update, rules}` - In dry-run mode.
    * `{:cleared, data_source}` / `{:would_clear, data_source}` - With
      `prune: true`.
    * `{:error, rules_or_data_source, exception}` - The request failed, or
      the rules name an unknown tier. Other templates are still submitted.

  ## Options

    * `:dry_run` - Compare the rules with Druid's without submitting
      anything.
    * `:prune` - Remove the rules of data sources that have no template, so
      they fall back to the cluster default. The default rules themselves are
      never removed. Can't be combined with `:only`. Defaults to `false`.
    * `:only` and the configuration options accepted by `render/2`.
  """
  @spec sync(Ecto.Repo.t(), Keyword.t()) :: [tuple()]
  def sync(repo, opts \\ []) do
    prune? = Keyword.get(opts, :prune, false)
    dry_run? = Keyword.get(opts, :dry_run, false)

    if prune? and Keyword.has_key?(opts, :only) do
      raise ArgumentError, ":prune can't be combined with :only"
    end

    rendered = render(repo, opts)
    config = SpecTemplates.config(repo, :retention, opts)
    request_opts = SpecTemplates.request_opts(repo, config)

    current = Druid.Client.Retention.all() |> Druid.Client.request!(request_opts)
    tiers = known_tiers(config, request_opts)

    submitted =
      Enum.map(rendered, fn rules ->
        submit(
          rules,
          Map.get(current, rules.data_source, []),
          tiers,
          dry_run?,
          config,
          request_opts
        )
      end)

    pruned =
      if prune? do
        defined = MapSet.new(rendered, & &1.data_source)

        current
        |> Enum.reject(fn {ds, rules} ->
          ds == "_default" or rules == [] or MapSet.member?(defined, ds)
        end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()
        |> Enum.map(&clear(&1, dry_run?, config, request_opts))
      else
        []
      end

    submitted ++ pruned
  end

  defp known_tiers(config, request_opts) do
    case Keyword.get(config, :tiers) do
      false -> nil
      nil -> Druid.Client.Retention.tiers() |> Druid.Client.request!(request_opts) |> MapSet.new()
      tiers -> MapSet.new(tiers)
    end
  end

  defp submit(rules, current, tiers, dry_run?, config, request_opts) do
    check_tiers!(rules, tiers)

    cond do
      normalize(rules.rules) == normalize(current) ->
        {:unchanged, rules}

      dry_run? ->
        if current == [], do: {:would_create, rules}, else: {:would_update, rules}

      true ->
        Druid.Client.Retention.set(rules.data_source, rules.rules, audit(config, rules.name))
        |> Druid.Client.request!(request_opts)

        if current == [], do: {:created, rules}, else: {:updated, rules}
    end
  rescue
    error -> {:error, rules, error}
  end

  defp clear(data_source, true = _dry_run?, _config, _request_opts),
    do: {:would_clear, data_source}

  defp clear(data_source, false = _dry_run?, config, request_opts) do
    Druid.Client.Retention.set(data_source, [], audit(config, nil))
    |> Druid.Client.request!(request_opts)

    {:cleared, data_source}
  rescue
    error -> {:error, data_source, error}
  end

  defp audit(config, name) do
    comment =
      if name,
        do: "Synced from retention template #{name}",
        else: "Removed by Druid.Retention: no template"

    [
      author: Keyword.get(config, :author, "ecto_druid"),
      comment: Keyword.get(config, :comment, comment)
    ]
  end

  defp check_tiers!(_rules, nil), do: :ok

  defp check_tiers!(rules, tiers) do
    unknown =
      rules.rules
      |> normalize()
      |> Enum.flat_map(&Map.keys(Map.get(&1, "tieredReplicants") || %{}))
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(tiers, &1))

    if unknown != [] do
      raise Error,
            "#{rules.name} loads segments onto unknown tiers #{inspect(unknown)}. " <>
              "Known tiers: #{inspect(Enum.sort(tiers))}. Set the :tiers option " <>
              "if a tier has no Historicals yet"
    end
  end

  @doc """
  Fills in the defaults Druid applies to rules and puts intervals in the
  form Druid stores them, so rendered rules can be compared with Druid's.
  """
  @spec normalize([map()]) :: [map()]
  def normalize(rules), do: Enum.map(rules, &normalize_rule/1)

  defp normalize_rule(%{"type" => type} = rule) do
    rule
    |> default_if(type in @load_rules, "tieredReplicants", %{@default_tier => 2})
    |> default_if(type in @load_rules, "useDefaultTierForNull", true)
    |> default_if(type in @future_rules, "includeFuture", true)
    |> update_existing("interval", &normalize_interval/1)
  end

  defp normalize_rule(rule), do: rule

  defp default_if(rule, true, key, value), do: Map.put_new(rule, key, value)
  defp default_if(rule, false, _key, _value), do: rule

  defp update_existing(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end

  defp normalize_interval(interval) when is_binary(interval) do
    with [from, to] <- String.split(interval, "/"),
         {:ok, from} <- normalize_instant(from),
         {:ok, to} <- normalize_instant(to) do
      from <> "/" <> to
    else
      _ -> interval
    end
  end

  defp normalize_interval(interval), do: interval

  defp normalize_instant(value) do
    datetime =
      case DateTime.from_iso8601(value) do
        {:ok, datetime, _offset} ->
          datetime

        _ ->
          case NaiveDateTime.from_iso8601(value) do
            {:ok, naive} ->
              DateTime.from_naive!(naive, "Etc/UTC")

            _ ->
              case Date.from_iso8601(value) do
                {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
                _ -> nil
              end
          end
      end

    if datetime do
      # Druid stores instants in UTC with milliseconds: 2020-01-01T00:00:00.000Z
      {micro, _precision} = DateTime.truncate(datetime, :millisecond).microsecond
      {:ok, DateTime.to_iso8601(%{datetime | microsecond: {micro, 3}})}
    else
      :error
    end
  end

  defp render_rules({name, path}, root, config) do
    {data_source, rules} =
      case SpecTemplates.render!(name, path, root, config, Error) do
        list when is_list(list) ->
          {Path.basename(name), list}

        %{"dataSource" => ds, "rules" => list} when is_binary(ds) and is_list(list) ->
          {ds, list}

        _ ->
          raise Error,
                "#{name} must render a list of rules, or an object with " <>
                  "\"dataSource\" and \"rules\""
      end

    unless Enum.all?(rules, &match?(%{"type" => type} when is_binary(type), &1)) do
      raise Error, "#{name}: every rule must be an object with a \"type\""
    end

    %Rules{name: name, path: path, data_source: data_source, rules: rules}
  end
end
