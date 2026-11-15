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
  `Druid.Supervisors` for details.

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
  """

  alias Druid.SpecTemplates

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
    defexception [:message]
  end

  @default_path "priv/druid/lookups"
  @default_tier "__default"

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

    submitted ++ pruned
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
