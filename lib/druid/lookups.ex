defmodule Druid.Lookups do
  @moduledoc """
  Manages Druid lookups as EEx templates in your application, with the values
  that change between environments supplied from config.

  ## Templates

  Each `*.json.eex` file in the templates directory (default
  `priv/druid/lookups`) defines one lookup, named after the file. A template
  renders the lookup's `lookupExtractorFactory`, the part you'd write by
  hand:

      {
        "type": "cachedNamespace",
        "extractionNamespace": {
          "type": "jdbc",
          "connectorConfig": {
            "connectURI": <%= json @lookup_db.uri %>,
            "user": <%= json @lookup_db.user %>,
            "password": {"type": "environment", "variable": "LOOKUP_DB_PASSWORD"}
          },
          "table": "countries",
          "keyColumn": "code",
          "valueColumn": "name",
          "pollPeriod": <%= json @lookup_db.poll_period %>
        }
      }

  Lookups go in the `"__default"` tier, or the tier set by the `:tier`
  option. To put a lookup in another tier, place its template in a directory
  named after the tier: `priv/druid/lookups/realtime/countries.json.eex`.

  Druid stores each lookup with a version, and only replaces it when the new
  version sorts after the current one. `sync/2` handles this: it compares
  each rendered lookup with Druid's, and gives changed lookups a new
  timestamp version such as `"v20261115T093000Z"`.

  Templates work the same way as supervisor spec templates: `@name` reads an
  assign (and raises if it's missing), `json/1` encodes a value, and
  `partial/1,2` renders a shared `_name.json.eex` fragment. See
  `Druid.Supervisors` for details. `@lookup_name` holds the lookup's name.

  ## Generating lookups from schemas

  If you query a lookup through an `Ecto.Druid.Lookup` schema, the schema can
  describe how it's loaded too, and the template can generate the factory
  with `lookup_factory`, the way supervisor templates use `data_schema`:

      <%= lookup_factory MyApp.Countries, connector: @lookup_db, poll_period: "PT10M" %>

  It raises if the template's name doesn't match the schema's lookup. See
  `Ecto.Druid.Lookup` and `Ecto.Druid.Lookup.Spec.factory/2`.

  Keep secrets such as database passwords out of templates. Druid can read
  them from its own environment with a password provider, as above.

  ## Configuration

  Configure lookups under the `:lookups` key of your Druid repo's config:

      config :my_app, MyApp.DruidRepo,
        lookups: [
          # The lookups API lives on the Router/Coordinator, not the Broker.
          host: System.get_env("DRUID_ROUTER_HOST", "localhost"),
          port: 8888,
          assigns: %{
            lookup_db: %{
              uri: System.get_env("LOOKUP_DB_URI"),
              user: System.get_env("LOOKUP_DB_USER"),
              poll_period: "PT10M"
            }
          },
          # Per-template assigns, keyed by template name.
          specs: %{"countries" => %{lookup_db: %{poll_period: "PT1H"}}}
        ]

  The supported options are:

    * `:path` - The templates directory. A relative path is resolved against
      the repo's OTP app directory. Defaults to `"priv/druid/lookups"`.
    * `:tier` - The tier for templates that aren't in a tier directory.
      Defaults to `"__default"`.
    * `:assigns` - Assigns available to every template.
    * `:specs` - A map of template name to assigns for that template only.
    * `:host`, `:port`, `:scheme` - Where to send lookups API requests.
      Default to the repo's values.

  Every option can also be given to `render/2` and `sync/2` directly, which
  take precedence over config.

  ## Applying lookups

      mix druid.lookups.render          # print the rendered lookups
      mix druid.lookups.sync --dry-run  # show what would change
      mix druid.lookups.sync            # submit them

  In a release, call `sync/2` instead, the same way as
  `Druid.Supervisors.sync/2`.

  ## Waiting for lookups to load

  Druid loads a new or changed lookup onto its nodes in the background, so
  queries can miss it, or fail with "Lookup not found", for a while after
  `sync/2` returns. Pass `wait: true` to return only once every synced
  lookup is loaded, or call `await/3`:

      Druid.Lookups.sync(MyApp.DruidRepo, wait: true, timeout: 60_000)
      :ok = Druid.Lookups.await(MyApp.DruidRepo, ["countries"], timeout: 60_000)

  A lookup is loaded once every node in its tier has its current version:
  Brokers, Historicals, and streaming ingestion tasks unless their spec sets
  `"lookupLoadingMode": "NONE"`. The Coordinator checks the nodes every
  `druid.manager.lookups.period`, two minutes by default, so waiting can
  take up to twice that. Lower it, for example to `5000`, on clusters used
  for tests.
  """

  alias Druid.{Poll, SpecTemplates}

  defmodule Lookup do
    @moduledoc """
    A rendered lookup.

      * `:name` - The template's path relative to the templates directory,
        without its extension.
      * `:path` - The template's absolute path.
      * `:tier` - The lookup's tier.
      * `:lookup` - The lookup's name.
      * `:factory` - The rendered `lookupExtractorFactory`, decoded from JSON.
    """
    @type t :: %__MODULE__{
            name: String.t(),
            path: Path.t(),
            tier: String.t(),
            lookup: String.t(),
            factory: map()
          }
    defstruct [:name, :path, :tier, :lookup, :factory]
  end

  defmodule Error do
    @moduledoc """
    Raised when a lookup template can't be rendered, and returned when
    lookups don't load in time.

      * `:reason` - `:timeout` when waiting timed out, `nil` for a template
        error.
      * `:pending` - When waiting timed out, a map of each lookup that
        wasn't loaded, as `"tier/name"`, to the nodes that hadn't loaded it.
    """
    @type t :: %__MODULE__{
            message: String.t(),
            reason: :timeout | nil,
            pending: %{String.t() => [String.t()]} | nil
          }
    defexception [:message, :reason, :pending]
  end

  @default_path "priv/druid/lookups"
  @default_tier "__default"
  @default_poll_interval 2_000

  @doc """
  Renders every lookup template for `repo`.

  Raises if a template fails to render, doesn't render a JSON object with a
  `"type"`, or defines the same lookup as another template.

  ## Options

    * `:only` - A list of template names to render. Defaults to all of them.
    * any option from the "Configuration" section of the module docs.
  """
  @spec render(Ecto.Repo.t(), Keyword.t()) :: [Lookup.t()]
  def render(repo, opts \\ []) do
    config = SpecTemplates.config(repo, :lookups, opts)
    root = SpecTemplates.root!(repo, config, @default_path, Error, "lookup")
    default_tier = Keyword.get(config, :tier, @default_tier)

    root
    |> SpecTemplates.discover()
    |> SpecTemplates.filter_only(Keyword.get(opts, :only), Error, "lookup")
    |> Enum.map(&render_lookup(&1, root, config, default_tier))
    |> SpecTemplates.check_unique!(
      &"#{&1.tier}/#{&1.lookup}",
      & &1.name,
      Error,
      "multiple templates define the same lookup"
    )
  end

  @doc """
  Renders the lookups for `repo` and submits the ones that changed.

  Returns one result per template, plus one per pruned lookup:

    * `{:created, lookup}` - No lookup with this name existed in its tier.
    * `{:updated, lookup}` - The lookup changed and got a new version.
    * `{:unchanged, lookup}` - The lookup matched Druid's.
    * `{:would_create, lookup}` / `{:would_update, lookup}` - In dry-run mode.
    * `{:deleted, "tier/name"}` / `{:would_delete, "tier/name"}` - With
      `prune: true`.
    * `{:error, lookup_or_name, exception}` - The request failed. Other
      lookups are still submitted.

  Lookups are initialized on the cluster first if it has none yet.

  ## Options

    * `:dry_run` - Compare the lookups with Druid's without submitting
      anything.
    * `:prune` - Delete lookups, in any tier, that have no template. Can't be
      combined with `:only`. Defaults to `false`.
    * `:wait` - When `true`, wait until every created, updated and unchanged
      lookup is loaded (see "Waiting for lookups to load" in the module
      docs). A lookup that isn't loaded by the `:timeout` is returned as
      `{:error, lookup, %Druid.Lookups.Error{reason: :timeout}}`. Defaults to
      `false`.
    * `:timeout`, `:poll_interval` - As in `await/3`, when waiting.
    * `:only` and the configuration options accepted by `render/2`.
  """
  @spec sync(Ecto.Repo.t(), Keyword.t()) :: [tuple()]
  def sync(repo, opts \\ []) do
    prune? = Keyword.get(opts, :prune, false)
    dry_run? = Keyword.get(opts, :dry_run, false)

    if prune? and Keyword.has_key?(opts, :only) do
      raise ArgumentError, ":prune can't be combined with :only"
    end

    lookups = render(repo, opts)
    request_opts = SpecTemplates.request_opts(repo, SpecTemplates.config(repo, :lookups, opts))
    current = current_lookups(request_opts)

    if current == :uninitialized and not dry_run? and lookups != [] do
      Druid.Client.Lookup.initialize() |> Druid.Client.request!(request_opts)
    end

    current = if current == :uninitialized, do: %{}, else: current

    submitted =
      Enum.map(lookups, fn lookup ->
        existing = get_in(current, [lookup.tier, lookup.lookup])
        submit(lookup, existing, dry_run?, request_opts)
      end)

    pruned =
      if prune? do
        defined = MapSet.new(lookups, &{&1.tier, &1.lookup})

        for {tier, tier_lookups} <- Enum.sort(current),
            {name, _} <- Enum.sort(tier_lookups),
            not MapSet.member?(defined, {tier, name}) do
          delete(tier, name, dry_run?, request_opts)
        end
      else
        []
      end

    results = submitted ++ pruned

    if Keyword.get(opts, :wait, false) and not dry_run? do
      wait_for_synced(results, request_opts, opts)
    else
      results
    end
  end

  defp wait_for_synced(results, request_opts, opts) do
    keys =
      for {status, %Lookup{} = lookup} <- results,
          status in [:created, :updated, :unchanged],
          do: key(lookup)

    case await_keys(keys, request_opts, opts) do
      :ok ->
        results

      {:error, %Error{reason: :timeout, pending: pending}} ->
        Enum.map(results, fn
          {status, %Lookup{} = lookup} = result when status in [:created, :updated, :unchanged] ->
            case Map.fetch(pending, key(lookup)) do
              {:ok, nodes} -> {:error, lookup, timeout_error(%{key(lookup) => nodes})}
              :error -> result
            end

          result ->
            result
        end)

      {:error, error} ->
        Enum.map(results, fn
          {status, %Lookup{} = lookup} when status in [:created, :updated, :unchanged] ->
            {:error, lookup, error}

          result ->
            result
        end)
    end
  end

  @doc """
  Waits until lookups are loaded on every node of their tier.

  Each lookup is a `Druid.Lookups.Lookup` from `render/2`, a `{tier, name}`
  tuple, a `"tier/name"` string, or a lookup name in the default tier (the
  `:tier` option, `"__default"` unless configured). A template name works
  too, since a template in a tier directory is named `"tier/name"`.

  Returns `:ok` once they're all loaded,
  `{:error, %Druid.Lookups.Error{reason: :timeout}}` when some aren't by the
  timeout, with the nodes that hadn't loaded them in `:pending`, and
  `{:error, exception}` when a request fails, including the 404 for a lookup
  that doesn't exist.

  See "Waiting for lookups to load" in the module docs for how long this
  can take.

  ## Options

    * `:timeout` - How long to wait in milliseconds. Defaults to `:infinity`.
    * `:poll_interval` - How often to check, in milliseconds. Defaults to
      `#{@default_poll_interval}`.
    * `:tier`, `:host`, `:port`, `:scheme` - As in the "Configuration"
      section of the module docs.
  """
  @spec await(Ecto.Repo.t(), [Lookup.t() | {String.t(), String.t()} | String.t()], Keyword.t()) ::
          :ok | {:error, Exception.t()}
  def await(repo, lookups, opts \\ []) when is_list(lookups) do
    config = SpecTemplates.config(repo, :lookups, opts)
    default_tier = Keyword.get(config, :tier, @default_tier)

    lookups
    |> Enum.map(&key(&1, default_tier))
    |> Enum.uniq()
    |> await_keys(SpecTemplates.request_opts(repo, config), opts)
  end

  defp await_keys([], _request_opts, _opts), do: :ok

  defp await_keys(keys, request_opts, opts) do
    deadline = Poll.deadline(Keyword.get(opts, :timeout, :infinity))
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)

    case Poll.poll(deadline, poll_interval, fn -> check_loaded(keys, request_opts) end) do
      {:ok, :loaded} -> :ok
      {:error, error} -> {:error, error}
      {:timeout, pending} -> {:error, timeout_error(pending || Map.new(keys, &{&1, []}))}
    end
  end

  # Returns {:wait, pending} with each lookup that isn't loaded yet and the
  # nodes that haven't loaded it.
  defp check_loaded(keys, request_opts) do
    Enum.reduce_while(keys, %{}, fn key, pending ->
      [tier, name] = String.split(key, "/", parts: 2)
      request = Druid.Client.Lookup.status(tier, name, detailed: true)

      case Druid.Client.request(request, request_opts) do
        {:ok, %{"loaded" => true}} -> {:cont, pending}
        {:ok, status} -> {:cont, Map.put(pending, key, status["pendingNodes"] || [])}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:error, error} -> {:error, error}
      pending when map_size(pending) == 0 -> {:done, :loaded}
      pending -> {:wait, pending}
    end
  end

  defp timeout_error(pending) do
    details =
      pending
      |> Enum.sort()
      |> Enum.map_join(", ", fn
        {key, []} -> key
        {key, nodes} -> "#{key} (not yet on #{Enum.join(nodes, ", ")})"
      end)

    %Error{
      message: "timed out waiting for lookups to load: #{details}",
      reason: :timeout,
      pending: pending
    }
  end

  defp key(%Lookup{tier: tier, lookup: lookup}), do: "#{tier}/#{lookup}"

  defp key(%Lookup{} = lookup, _default_tier), do: key(lookup)

  defp key({tier, name}, _default_tier) when is_binary(tier) and is_binary(name),
    do: "#{tier}/#{name}"

  defp key(name, default_tier) when is_binary(name) do
    if String.contains?(name, "/"), do: name, else: "#{default_tier}/#{name}"
  end

  defp current_lookups(request_opts) do
    Druid.Client.Lookup.all() |> Druid.Client.request!(request_opts)
  rescue
    error in Druid.Client.RequestError ->
      if error.status == 404, do: :uninitialized, else: reraise(error, __STACKTRACE__)
  end

  defp submit(lookup, existing, dry_run?, request_opts) do
    cond do
      existing && existing["lookupExtractorFactory"] == lookup.factory ->
        {:unchanged, lookup}

      dry_run? ->
        if existing, do: {:would_update, lookup}, else: {:would_create, lookup}

      true ->
        version = next_version(existing && existing["version"], DateTime.utc_now())

        Druid.Client.Lookup.set(lookup.tier, lookup.lookup, version, lookup.factory)
        |> Druid.Client.request!(request_opts)

        if existing, do: {:updated, lookup}, else: {:created, lookup}
    end
  rescue
    error -> {:error, lookup, error}
  end

  defp delete(tier, name, true = _dry_run?, _request_opts), do: {:would_delete, "#{tier}/#{name}"}

  defp delete(tier, name, false = _dry_run?, request_opts) do
    Druid.Client.Lookup.delete(tier, name) |> Druid.Client.request!(request_opts)
    {:deleted, "#{tier}/#{name}"}
  rescue
    error -> {:error, "#{tier}/#{name}", error}
  end

  @doc """
  Returns the version to give a changed lookup: a timestamp version for
  `now`, or, if that doesn't sort after `current`, `current` with the
  timestamp appended, which always does.
  """
  @spec next_version(String.t() | nil, DateTime.t()) :: String.t()
  def next_version(current, now) do
    version = "v" <> Calendar.strftime(now, "%Y%m%dT%H%M%SZ")

    if is_nil(current) or version > current do
      version
    else
      current <> "-" <> version
    end
  end

  defp render_lookup({name, path}, root, config, default_tier) do
    {tier, lookup} =
      case Path.split(name) do
        [lookup] ->
          {default_tier, lookup}

        [tier, lookup] ->
          {tier, lookup}

        _ ->
          raise Error,
                "#{name}: lookup templates go directly in the templates directory " <>
                  "or in a tier directory"
      end

    # Lets lookup_factory check the template against its schema.
    config =
      Keyword.update(config, :assigns, %{lookup_name: lookup}, fn assigns ->
        assigns |> Map.new() |> Map.put(:lookup_name, lookup)
      end)

    factory =
      case SpecTemplates.render!(name, path, root, config, Error) do
        %{"lookupExtractorFactory" => _} ->
          raise Error,
                "#{name} should render only the lookupExtractorFactory. The version " <>
                  "is added when the lookup is submitted"

        %{"type" => type} = factory when is_binary(type) ->
          factory

        _ ->
          raise Error, "#{name} must render a JSON object with a \"type\""
      end

    %Lookup{name: name, path: path, tier: tier, lookup: lookup, factory: factory}
  end
end
