defmodule Druid.Supervisors.Template do
  @moduledoc """
  Renders spec templates: supervisor specs (`Druid.Supervisors`), compaction
  configs (`Druid.Compaction`), retention rules (`Druid.Retention`) and
  lookups (`Druid.Lookups`). See
  `Druid.Supervisors` for the template format.

  Templates are EEx with a few differences from plain `EEx.eval_file/3`:

    * Referencing an assign that wasn't given (`@missing`) raises instead of
      rendering an empty string, so a typo can't silently produce bad JSON.
    * `json/1` and `partial/1,2` are available inside templates.
  """

  defmodule Error do
    defexception [:message]
  end

  @partials_key :__druid_partials_root__

  @doc """
  Renders the template at `path` with `assigns`. `root` is the directory
  partials are resolved against.
  """
  @spec render_file(Path.t(), map(), Path.t()) :: String.t()
  def render_file(path, assigns, root) do
    assigns = Map.put(assigns, @partials_key, root)

    compiled = EEx.compile_file(path, engine: __MODULE__.Engine)

    quoted =
      quote do
        import Druid.Supervisors.Template.Helpers
        unquote(compiled)
      end

    {result, _binding} = Code.eval_quoted(quoted, [assigns: assigns], file: path)
    result
  end

  @doc false
  def render_partial(name, assigns, extra) do
    root = Map.fetch!(assigns, @partials_key)
    path = partial_path(root, name)

    unless File.regular?(path) do
      raise Error, "partial #{inspect(name)} not found, expected #{path}"
    end

    render_file(path, Map.merge(assigns, Map.new(extra)), root)
  end

  defp partial_path(root, name) do
    dir = Path.dirname(name)
    base = Path.basename(name)
    Path.join([root, dir, "_" <> base <> ".json.eex"]) |> Path.expand()
  end

  @doc false
  def fetch_assign!(assigns, key) do
    case Map.fetch(assigns, key) do
      {:ok, value} ->
        value

      :error ->
        available =
          assigns
          |> Map.keys()
          |> Enum.reject(&(&1 == @partials_key))
          |> Enum.sort()
          |> Enum.map_join(", ", &"@#{&1}")

        raise Error, "assign @#{key} is not set. Available assigns: #{available}"
    end
  end

  defmodule Engine do
    @moduledoc false
    @behaviour EEx.Engine

    @impl true
    defdelegate init(opts), to: EEx.Engine

    @impl true
    defdelegate handle_body(state), to: EEx.Engine

    @impl true
    defdelegate handle_text(state, meta, text), to: EEx.Engine

    @impl true
    defdelegate handle_begin(state), to: EEx.Engine

    @impl true
    defdelegate handle_end(state), to: EEx.Engine

    @impl true
    def handle_expr(state, marker, expr) do
      EEx.Engine.handle_expr(state, marker, Macro.prewalk(expr, &strict_assign/1))
    end

    defp strict_assign({:@, meta, [{name, _, context}]})
         when is_atom(name) and is_atom(context) do
      quote line: meta[:line] || 0 do
        Druid.Supervisors.Template.fetch_assign!(var!(assigns), unquote(name))
      end
    end

    defp strict_assign(expr), do: expr
  end

  defmodule Helpers do
    @moduledoc """
    Functions available inside supervisor spec templates.
    """

    @doc """
    Encodes a value as JSON. Use it for any value that isn't a bare number, so
    strings get quoted and escaped, and maps and lists come out as JSON.

        "bootstrap.servers": <%= json @kafka_brokers %>,
        "consumerProperties": <%= json @consumer_properties %>
    """
    @spec json(term()) :: String.t()
    def json(value), do: Jason.encode!(value)

    @doc """
    Generates a whole `dataSchema` from a schema that uses `Ecto.Druid.Schema`.
    See `Ecto.Druid.Schema.Spec.data_schema/2` for options.

        "dataSchema": <%= data_schema MyApp.PageViewsHourly,
                            segment_granularity: "DAY",
                            filter: @filter %>
    """
    @spec data_schema(module(), Keyword.t()) :: String.t()
    def data_schema(schema, opts \\ []),
      do: json(Ecto.Druid.Schema.Spec.data_schema(schema, opts))

    @doc """
    Lists the time-partitioned storage prefixes an interval covers, as a JSON
    array. Mainly for backfill task templates, where `@interval` is set. See
    `Druid.Tasks.partition_prefixes/4`.

        "prefixes": <%= partition_prefixes "s3://my-bucket/events", @interval,
                          "year=%Y/month=%m/day=%d/" %>
    """
    @spec partition_prefixes(String.t(), term(), String.t(), Keyword.t()) :: String.t()
    def partition_prefixes(base, interval, format, opts \\ []),
      do: json(Druid.Tasks.partition_prefixes(base, interval, format, opts))

    @doc """
    Generates a `timestampSpec`. See `Ecto.Druid.Schema.Spec.timestamp_spec/1`.
    """
    @spec timestamp_spec(module()) :: String.t()
    def timestamp_spec(schema), do: json(Ecto.Druid.Schema.Spec.timestamp_spec(schema))

    @doc """
    Generates a `dimensionsSpec`. See `Ecto.Druid.Schema.Spec.dimensions_spec/1`.
    """
    @spec dimensions_spec(module()) :: String.t()
    def dimensions_spec(schema), do: json(Ecto.Druid.Schema.Spec.dimensions_spec(schema))

    @doc """
    Generates a `metricsSpec`. Pass `combining: true` in compaction specs. See
    `Ecto.Druid.Schema.Spec.metrics_spec/2`.

        "metricsSpec": <%= metrics_spec MyApp.PageViewsHourly, combining: true %>
    """
    @spec metrics_spec(module(), Keyword.t()) :: String.t()
    def metrics_spec(schema, opts \\ []),
      do: json(Ecto.Druid.Schema.Spec.metrics_spec(schema, opts))

    @doc """
    Generates a lookup's `lookupExtractorFactory` from a schema that uses
    `Ecto.Druid.Lookup`. See `Ecto.Druid.Lookup.Spec.factory/2` for options.

        <%= lookup_factory MyApp.Countries, map: @countries %>

        <%= lookup_factory MyApp.Countries, connector: @lookup_db, poll_period: "PT10M" %>

    In a lookup template, raises if the template defines a different lookup
    from the schema's, so the template's file name and the schema can't
    drift apart.
    """
    defmacro lookup_factory(schema, opts \\ []) do
      quote do
        Druid.Supervisors.Template.Helpers.__lookup_factory__(
          unquote(schema),
          unquote(opts),
          var!(assigns)
        )
      end
    end

    @doc false
    def __lookup_factory__(schema, opts, assigns) do
      factory = Ecto.Druid.Lookup.Spec.factory(schema, opts)

      with {:ok, template_lookup} <- Map.fetch(assigns, :lookup_name),
           schema_lookup when schema_lookup != template_lookup <- schema.__lookup__(:name) do
        raise Druid.Supervisors.Template.Error,
              "this template defines the #{inspect(template_lookup)} lookup, but " <>
                "#{inspect(schema)} reads #{inspect(schema_lookup)}. Rename the template " <>
                "or set the schema's :name"
      end

      json(factory)
    end

    @doc """
    Renders a partial: a template that starts with `_` in the templates
    directory. `partial("index_spec")` renders `_index_spec.json.eex`, and
    `partial("shared/index_spec")` renders `shared/_index_spec.json.eex`.

    The partial sees the same assigns as the template that includes it, plus
    any `extra` assigns.

        "indexSpec": <%= partial "index_spec", complex_metric_compression: "zstd" %>
    """
    defmacro partial(name, extra \\ []) do
      quote do
        Druid.Supervisors.Template.render_partial(
          unquote(name),
          var!(assigns),
          unquote(extra)
        )
      end
    end
  end
end
