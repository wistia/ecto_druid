defmodule Ecto.Druid.Schema.Spec do
  @moduledoc """
  Builds the parts of a Druid ingestion spec from a schema that uses
  `Ecto.Druid.Schema`.

  The functions return maps ready to encode as JSON. Supervisor spec
  templates have helpers of the same names that return JSON (see
  `Druid.Supervisors.Template.Helpers`).
  """

  @doc """
  Builds a complete `dataSchema` for a supervisor or batch ingestion spec.

  ## Options

    * `:data_source` - Defaults to the schema's source.
    * `:segment_granularity` - Defaults to `"HOUR"`.
    * `:query_granularity` - Defaults to `"NONE"`.
    * `:rollup` - Defaults to `true` if the schema has metrics.
    * `:intervals` - The `granularitySpec` intervals of a batch ingestion
      task: the time ranges to ingest, which a task that doesn't append
      replaces. Strings or `Ecto.Druid.Interval`s.
    * `:transforms` - Extra `transformSpec` transforms, added after the ones
      generated for dimensions with `:from` (see `transforms/1`). Raises if
      one has the same name as a generated transform.
    * `:filter` - A `transformSpec` filter.
    * `:merge` - A map deep-merged into the result, for anything else, for
      example `%{"dimensionsSpec" => %{"dimensionExclusions" => ["x"]}}`.

  ## Examples

      Ecto.Druid.Schema.Spec.data_schema(MyApp.PageViewsHourly, segment_granularity: "DAY")
  """
  @spec data_schema(module(), Keyword.t()) :: map()
  def data_schema(schema, opts \\ []) do
    metrics = metrics_spec(schema)

    transforms = merge_transforms(schema, transforms(schema), Keyword.get(opts, :transforms, []))

    transform_spec =
      %{}
      |> put_present("transforms", if(transforms == [], do: nil, else: transforms))
      |> put_present("filter", Keyword.get(opts, :filter))

    %{
      "dataSource" => Keyword.get_lazy(opts, :data_source, fn -> source!(schema) end),
      "timestampSpec" => timestamp_spec(schema),
      "dimensionsSpec" => dimensions_spec(schema),
      "metricsSpec" => metrics,
      "granularitySpec" =>
        put_present(
          %{
            "type" => "uniform",
            "segmentGranularity" => Keyword.get(opts, :segment_granularity, "HOUR"),
            "queryGranularity" => Keyword.get(opts, :query_granularity, "NONE"),
            "rollup" => Keyword.get(opts, :rollup, metrics != [])
          },
          "intervals",
          intervals(Keyword.get(opts, :intervals))
        )
    }
    |> put_present("transformSpec", if(transform_spec == %{}, do: nil, else: transform_spec))
    |> deep_merge(Keyword.get(opts, :merge, %{}))
  end

  defp intervals(nil), do: nil
  defp intervals(intervals), do: Enum.map(List.wrap(intervals), &Ecto.Druid.Interval.to_iso8601/1)

  @doc """
  Builds the transforms for dimensions that read an input field with a
  different name (`dimension/3` with `:from`). Each copies the input field
  into a field named after the column, which the dimension then reads:

      dimension :visitor_key, :string, from: "user_key"

      %{"type" => "expression", "name" => "visitor_key", "expression" => ~s("user_key")}

  `data_schema/2` includes these automatically.
  """
  @spec transforms(module()) :: [map()]
  def transforms(schema) do
    for %{from: from} = dim <- druid!(schema, :dimensions), from != nil do
      %{"type" => "expression", "name" => dim.column, "expression" => quote_identifier(from)}
    end
  end

  # Druid expressions quote identifiers with double quotes, escaping \ and ".
  defp quote_identifier(name) do
    ~s(") <> String.replace(name, ["\\", ~s(")], &("\\" <> &1)) <> ~s(")
  end

  defp merge_transforms(schema, generated, extra) do
    generated_names = MapSet.new(generated, & &1["name"])

    clashes =
      extra
      |> Enum.map(&(&1["name"] || &1[:name]))
      |> Enum.filter(&MapSet.member?(generated_names, to_string(&1)))

    if clashes != [] do
      raise ArgumentError,
            "transforms #{inspect(clashes)} clash with the ones #{inspect(schema)} generates " <>
              "for dimensions with :from. Remove :from from the dimension or the transform"
    end

    generated ++ extra
  end

  @doc """
  Builds the `timestampSpec` from the schema's `timestamp/2` column.
  """
  @spec timestamp_spec(module()) :: map()
  def timestamp_spec(schema) do
    case druid!(schema, :timestamp) do
      nil ->
        raise ArgumentError,
              "#{inspect(schema)} has no Druid timestamp. Define one with timestamp/2"

      ts ->
        %{"column" => ts.column, "format" => ts.format}
        |> put_present("missingValue", ts.missing_value)
        |> Map.merge(ts.extra)
    end
  end

  @doc """
  Builds the `dimensionsSpec` from the schema's `dimension/3` columns, in the
  order they're defined.
  """
  @spec dimensions_spec(module()) :: map()
  def dimensions_spec(schema) do
    dimensions =
      for dim <- druid!(schema, :dimensions) do
        Map.merge(%{"type" => dim.type, "name" => dim.column}, dim.extra)
      end

    %{"dimensions" => dimensions}
  end

  @doc """
  Builds the `metricsSpec` from the schema's `metric/3` columns, in the order
  they're defined.

  ## Options

    * `:combining` - When `true`, build aggregators that re-aggregate the
      stored columns instead of ingesting input fields: each reads its own
      column, and `count` becomes a `longSum`. Use this for compaction specs.
      Defaults to `false`.
  """
  @spec metrics_spec(module(), Keyword.t()) :: [map()]
  def metrics_spec(schema, opts \\ []) do
    combining? = Keyword.get(opts, :combining, false)

    for metric <- druid!(schema, :metrics) do
      if combining? do
        %{"type" => metric.combining_type, "name" => metric.column, "fieldName" => metric.column}
      else
        put_present(%{"type" => metric.type, "name" => metric.column}, "fieldName", metric.from)
      end
      |> Map.merge(metric.extra)
    end
  end

  defp druid!(schema, key) do
    Code.ensure_loaded(schema)

    unless function_exported?(schema, :__druid__, 1) do
      raise ArgumentError, "#{inspect(schema)} must `use Ecto.Druid.Schema`"
    end

    schema.__druid__(key)
  end

  defp source!(schema) do
    schema.__schema__(:source) ||
      raise ArgumentError, "#{inspect(schema)} has no source. Pass :data_source"
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = l, %{} = r -> deep_merge(l, r)
      _key, _l, r -> r
    end)
  end
end
