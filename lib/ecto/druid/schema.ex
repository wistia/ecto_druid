defmodule Ecto.Druid.Schema do
  @moduledoc """
  Describes a Druid datasource with an Ecto schema, including how its columns
  are ingested, so the `dataSchema` part of a supervisor spec can be generated
  from it.

      defmodule MyApp.PageViewsHourly do
        use Ecto.Druid.Schema

        @primary_key false
        schema "page_views_hourly" do
          timestamp :time, column: "ts", format: "millis"

          dimension :country, :string
          dimension :tags, {:array, :string}
          dimension :duration_ms, :integer
          dimension :visitor_key, :string, from: "user_key"

          metric :views, :integer, aggregate: :count
          metric :watch_time, :float, aggregate: :sum, from: "watch_seconds"
          metric :unique_visitors, Ecto.Druid.HLLSketch, from: "visitor_id", lg_k: 12
        end
      end

  `timestamp/2`, `dimension/3` and `metric/3` each define a normal Ecto
  field, so the schema is queried like any other. They also record how the
  column is ingested, which `__druid__/1` returns and the spec builders in
  `Ecto.Druid.Schema.Spec` use. Fields defined with plain `field/3` are
  queryable but left out of generated specs.

  `projection/2` declares a pre-aggregated summary that Druid builds into
  each segment and uses for queries it can answer. It defines no field.

  In a supervisor spec template, generate the whole `dataSchema` with the
  `data_schema/2` helper:

      "dataSchema": <%= data_schema MyApp.PageViewsHourly, segment_granularity: "DAY" %>

  ## Options

  Each macro accepts these Ecto field options and passes them to `field/3`:
  #{Enum.map_join([:source, :default, :redact, :load_in_query, :virtual, :read_after_writes, :writable, :skip_default_validation], ", ", &"`#{inspect(&1)}`")}.
  `:source` also sets the Druid column name.

  Any other options are Druid options. The ones not listed for each macro
  below are passed through to the generated JSON, with `snake_case` keys
  converted to `camelCase` (`lg_k: 12` becomes `"lgK": 12`). Use a string
  key to pass one through unchanged.
  """

  @ecto_field_opts [
    :source,
    :default,
    :redact,
    :load_in_query,
    :virtual,
    :read_after_writes,
    :writable,
    :skip_default_validation
  ]

  # Default aggregators for Druid complex types: {ingest type, combining type}.
  # The combining type re-aggregates an already-aggregated column, as
  # compaction does.
  @complex_aggregators %{
    Ecto.Druid.HLLSketch => {"HLLSketchBuild", "HLLSketchMerge"},
    Ecto.Druid.ThetaSketch => {"thetaSketch", "thetaSketch"},
    Ecto.Druid.QuantilesSketch => {"quantilesDoublesSketch", "quantilesDoublesSketch"},
    Ecto.Druid.TupleSketch => {"arrayOfDoublesSketch", "arrayOfDoublesSketch"}
  }

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Ecto.Druid.Schema,
        only: [
          timestamp: 1,
          timestamp: 2,
          dimension: 2,
          dimension: 3,
          metric: 2,
          metric: 3,
          projection: 2
        ]

      Module.register_attribute(__MODULE__, :druid_timestamp, accumulate: true)
      Module.register_attribute(__MODULE__, :druid_dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :druid_metrics, accumulate: true)
      Module.register_attribute(__MODULE__, :druid_projections, accumulate: true)

      @before_compile Ecto.Druid.Schema
    end
  end

  @doc """
  Defines the `__time` column as field `name`, of type `Ecto.Druid.Timestamp`.

  ## Options

    * `:column` - The input field holding the timestamp. Defaults to
      `"timestamp"`.
    * `:format` - `"iso"`, `"millis"`, `"posix"`, `"auto"`, or a Joda
      format string. Defaults to `"auto"`.
    * `:missing_value` - The timestamp to use for rows without one.
  """
  defmacro timestamp(name, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      {ecto_opts, druid_opts} = Ecto.Druid.Schema.__split_opts__(opts)
      Ecto.Schema.field(name, Ecto.Druid.Timestamp, Keyword.put(ecto_opts, :source, :__time))
      @druid_timestamp Ecto.Druid.Schema.__timestamp__(__MODULE__, name, druid_opts)
    end
  end

  @doc """
  Defines a field that is ingested as a dimension.

  The dimension type comes from the Ecto type:

  | Ecto type | Druid dimension type |
  | --- | --- |
  | `:string`, `:binary_id` | `string` |
  | `:integer`, `:id`, `:boolean` | `long` |
  | `:float`, `:decimal` | `double` |
  | `:map` | `json` |
  | `{:array, _}` | `auto` (an ARRAY column) |

  ## Options

    * `:druid_type` - Use this dimension type instead.
    * `:multi_value` - For `{:array, :string}`, ingest a multi-value string
      dimension instead of an ARRAY column.
    * `:from` - The input field to read, when it has a different name than
      the column. Druid dimensions always read the input field of their own
      name, so this generates an expression transform that copies the field
      (see `Ecto.Druid.Schema.Spec.transforms/1`).

          dimension :visitor_key, :string, from: "user_key"
  """
  defmacro dimension(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      {ecto_opts, druid_opts} = Ecto.Druid.Schema.__split_opts__(opts)
      Ecto.Schema.field(name, type, ecto_opts)

      @druid_dimensions Ecto.Druid.Schema.__dimension__(
                          __MODULE__,
                          name,
                          type,
                          ecto_opts,
                          druid_opts
                        )
    end
  end

  @doc """
  Defines a field that is ingested as a metric (an aggregation).

  ## Options

    * `:aggregate` - How to aggregate rows:
      * `:count` - Count ingested rows. Reads no input field.
      * `:sum`, `:min`, `:max`, `:first`, `:last` - Combined with the
        Ecto type: `:integer` gives `longSum`, `:float` gives `doubleSum`, and
        so on. `:first` and `:last` also work with `:string`.
      * a string - Use this Druid aggregator type as is, for example
        `"fixedBucketsHistogram"`. Pass its parameters as other options.

      Defaults to the type's own aggregator for Druid complex types
      (`Ecto.Druid.HLLSketch` builds an `HLLSketchBuild`,
      `Ecto.Druid.ThetaSketch` a `thetaSketch`, `Ecto.Druid.QuantilesSketch` a
      `quantilesDoublesSketch`, and `Ecto.Druid.TupleSketch` an
      `arrayOfDoublesSketch`). Required for other types.

    * `:from` - The input field to aggregate. Defaults to the column name.
    * `:combine_as` - The aggregator type that re-aggregates this column when
      compacting, if a string `:aggregate` needs a different one.
  """
  defmacro metric(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      {ecto_opts, druid_opts} = Ecto.Druid.Schema.__split_opts__(opts)
      Ecto.Schema.field(name, type, ecto_opts)

      @druid_metrics Ecto.Druid.Schema.__metric__(
                       __MODULE__,
                       name,
                       type,
                       ecto_opts,
                       druid_opts
                     )
    end
  end

  @doc """
  Declares a [projection](https://druid.apache.org/docs/latest/querying/projections):
  a summary of the data that Druid builds into each segment at ingestion
  time, next to the rows. A query whose grouping and aggregations the
  summary can answer reads it instead of the rows; nothing in the query
  names it. Druid marks projections experimental.

      projection :channel_hourly,
        granularity: :hour,
        group_by: [:channel],
        aggregate: [added: {:sum, :added}, edits: :count]

  answers queries such as

      from e in MyApp.Edits,
        group_by: [time_floor(e.time, "PT1H"), e.channel],
        select: {time_floor(e.time, "PT1H"), e.channel, sum(e.added), count()}

  and also coarser time buckets (`"P1D"`), fewer grouping columns, and
  filters on them.

  `Ecto.Druid.Schema.Spec.data_schema/2` includes the schema's projections,
  so ingestion specs built from it build them. Segments written before a
  projection was added only get it when they're compacted with it (see
  `Ecto.Druid.Schema.Spec.projections/1`).

  ## Options

    * `:granularity` - Groups by `__time` floored to this period: `:second`,
      `:minute`, `:five_minute`, `:ten_minute`, `:fifteen_minute`,
      `:thirty_minute`, `:hour`, `:six_hour`, `:eight_hour`, `:day`, `:week`,
      `:month`, `:quarter`, `:year`, or an ISO 8601 period such as `"PT1H"`.
      Without it, the projection doesn't group by time.
    * `:group_by` - Dimension fields to group by, in sort order.
    * `:aggregate` - A keyword list of the aggregations to store, by name:
      * `:count` - Counts rows. On a rollup data source, sum its count
        metric instead.
      * `{:sum | :min | :max | :first | :last, field}` - Aggregates a
        dimension or metric field. Its type picks the aggregator: `:sum` of
        an integer is `longSum`, of a float `doubleSum`, and so on.
      * `{sketch_type, field}` - Builds a sketch, such as
        `{Ecto.Druid.HLLSketch, :user}`. Of a dimension it builds from the
        values (`HLLSketchBuild`); of a sketch metric it merges them
        (`HLLSketchMerge`).
      * `{type, field}` - A Druid aggregator type string, such as
        `{"doubleMean", :latency}`.
      * a map - A whole Druid aggregator, used as is with the name added.

      A three-element tuple takes extra aggregator options last:
      `{Ecto.Druid.HLLSketch, :user, lg_k: 14}`. Druid only uses a projection
      for a query whose aggregations match its aggregators, options included.

  Any other options are added to the projection's JSON, with `snake_case`
  keys converted to `camelCase`.
  """
  defmacro projection(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @druid_projections {name, opts}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    timestamp =
      case Module.get_attribute(env.module, :druid_timestamp) do
        [] ->
          nil

        [timestamp] ->
          timestamp

        _ ->
          raise CompileError,
            file: env.file,
            description: "#{inspect(env.module)} defines more than one Druid timestamp"
      end

    dimensions = env.module |> Module.get_attribute(:druid_dimensions) |> Enum.reverse()
    metrics = env.module |> Module.get_attribute(:druid_metrics) |> Enum.reverse()

    projections =
      env.module
      |> Module.get_attribute(:druid_projections)
      |> Enum.reverse()
      |> Enum.map(fn {name, opts} ->
        Ecto.Druid.Schema.__projection__(env.module, name, opts, dimensions, metrics)
      end)

    quote do
      @doc false
      def __druid__(:timestamp), do: unquote(Macro.escape(timestamp))
      def __druid__(:dimensions), do: unquote(Macro.escape(dimensions))
      def __druid__(:metrics), do: unquote(Macro.escape(metrics))
      def __druid__(:projections), do: unquote(Macro.escape(projections))
    end
  end

  @doc false
  def __split_opts__(opts), do: Keyword.split(opts, @ecto_field_opts)

  @doc false
  def __timestamp__(_module, name, opts) do
    {spec, extra} = Keyword.split(opts, [:column, :format, :missing_value])

    %{
      name: name,
      column: Keyword.get(spec, :column, "timestamp"),
      format: Keyword.get(spec, :format, "auto"),
      missing_value: Keyword.get(spec, :missing_value),
      extra: camelize_keys(extra)
    }
  end

  @doc false
  def __dimension__(module, name, type, ecto_opts, opts) do
    {multi_value, opts} = Keyword.pop(opts, :multi_value, false)
    {druid_type, opts} = Keyword.pop(opts, :druid_type)
    {from, opts} = Keyword.pop(opts, :from)
    column = column(name, ecto_opts)

    druid_type =
      druid_type || dimension_type(type, multi_value) ||
        raise ArgumentError,
              "#{inspect(module)}.#{name}: can't infer a Druid dimension type for " <>
                "#{inspect(type)}. Pass :druid_type"

    %{
      name: name,
      column: column,
      type: druid_type,
      from: if(from && to_string(from) != column, do: to_string(from)),
      extra: camelize_keys(opts)
    }
  end

  defp dimension_type(type, _) when type in [:string, :binary_id], do: "string"
  defp dimension_type(type, _) when type in [:integer, :id, :boolean], do: "long"
  defp dimension_type(type, _) when type in [:float, :decimal], do: "double"
  defp dimension_type(:map, _), do: "json"
  defp dimension_type({:array, :string}, true), do: "string"
  defp dimension_type({:array, _}, _), do: "auto"
  defp dimension_type(_type, _), do: nil

  @doc false
  def __metric__(module, name, type, ecto_opts, opts) do
    {aggregate, opts} = Keyword.pop(opts, :aggregate)
    {from, opts} = Keyword.pop(opts, :from)
    {combine_as, opts} = Keyword.pop(opts, :combine_as)
    column = column(name, ecto_opts)

    {agg_type, combining_type} =
      aggregator(type, aggregate) ||
        raise ArgumentError,
              "#{inspect(module)}.#{name}: can't aggregate #{inspect(type)} with " <>
                "#{inspect(aggregate)}. Pass :aggregate as :count, :sum, :min, :max, " <>
                ":first, :last, or a Druid aggregator type string"

    %{
      name: name,
      column: column,
      type: agg_type,
      combining_type: combine_as || combining_type,
      from: if(agg_type == "count", do: nil, else: from || column),
      extra: camelize_keys(opts)
    }
  end

  defp aggregator(_type, :count), do: {"count", "longSum"}
  defp aggregator(_type, aggregate) when is_binary(aggregate), do: {aggregate, aggregate}

  defp aggregator(type, nil) when is_map_key(@complex_aggregators, type),
    do: Map.fetch!(@complex_aggregators, type)

  defp aggregator(type, aggregate) when aggregate in [:sum, :min, :max, :first, :last] do
    prefix =
      case type do
        t when t in [:integer, :id] -> "long"
        t when t in [:float, :decimal] -> "double"
        :string when aggregate in [:first, :last] -> "string"
        _ -> nil
      end

    if prefix do
      agg = prefix <> (aggregate |> Atom.to_string() |> String.capitalize())
      {agg, agg}
    end
  end

  defp aggregator(_type, _aggregate), do: nil

  @granularity_periods %{
    second: "PT1S",
    minute: "PT1M",
    five_minute: "PT5M",
    ten_minute: "PT10M",
    fifteen_minute: "PT15M",
    thirty_minute: "PT30M",
    hour: "PT1H",
    six_hour: "PT6H",
    eight_hour: "PT8H",
    day: "P1D",
    week: "P1W",
    month: "P1M",
    quarter: "P3M",
    year: "P1Y"
  }

  # Builds a projection's JSON from the schema's dimensions and metrics. The
  # time bucket is a virtual column, which Druid groups by like a dimension.
  @doc false
  def __projection__(module, name, opts, dimensions, metrics) do
    {granularity, opts} = Keyword.pop(opts, :granularity)
    {group_by, opts} = Keyword.pop(opts, :group_by, [])
    {aggregate, opts} = Keyword.pop(opts, :aggregate, [])
    where = "#{inspect(module)} projection #{inspect(name)}"
    fields = Map.new(dimensions, &{&1.name, {:dimension, &1}})
    fields = Enum.into(metrics, fields, &{&1.name, {:metric, &1}})

    if aggregate == [] do
      raise ArgumentError, "#{where} needs at least one aggregation in :aggregate"
    end

    {virtual_columns, time} =
      case granularity do
        nil ->
          {[], []}

        granularity ->
          period = period!(where, granularity)

          {[
             %{
               "type" => "expression",
               "name" => "__gran",
               "expression" => "timestamp_floor(__time, '#{period}')",
               "outputType" => "LONG"
             }
           ], [%{"type" => "long", "name" => "__gran"}]}
      end

    grouping =
      Enum.map(group_by, fn field ->
        case Map.get(fields, field) do
          {:dimension, dim} -> %{"type" => dim.type, "name" => dim.column}
          _ -> raise ArgumentError, "#{where} can't group by #{inspect(field)}: not a dimension"
        end
      end)

    aggregators =
      Enum.map(aggregate, fn {agg_name, spec} ->
        projection_aggregator(where, to_string(agg_name), spec, fields)
      end)

    %{
      "type" => "aggregate",
      "name" => to_string(name),
      "groupingColumns" => time ++ grouping,
      "aggregators" => aggregators
    }
    |> then(
      &if virtual_columns == [], do: &1, else: Map.put(&1, "virtualColumns", virtual_columns)
    )
    |> Map.merge(camelize_keys(opts))
  end

  defp period!(_where, granularity) when is_map_key(@granularity_periods, granularity),
    do: Map.fetch!(@granularity_periods, granularity)

  defp period!(_where, "P" <> _ = period), do: period

  defp period!(where, other) do
    raise ArgumentError,
          "#{where} has an unknown :granularity #{inspect(other)}. Use one of " <>
            "#{inspect(Map.keys(@granularity_periods))} or an ISO 8601 period such as \"PT1H\""
  end

  defp projection_aggregator(_where, name, :count, _fields),
    do: %{"type" => "count", "name" => name}

  defp projection_aggregator(_where, name, %{} = aggregator, _fields),
    do: aggregator |> Map.new(fn {k, v} -> {to_string(k), v} end) |> Map.put("name", name)

  defp projection_aggregator(where, name, {kind, field}, fields),
    do: projection_aggregator(where, name, {kind, field, []}, fields)

  defp projection_aggregator(where, name, {kind, field, opts}, fields) do
    {source, column} =
      case Map.get(fields, field) do
        {:dimension, dim} -> {{:dimension, dim}, dim.column}
        {:metric, metric} -> {{:metric, metric}, metric.column}
        nil -> raise ArgumentError, "#{where} can't aggregate #{inspect(field)}: no such column"
      end

    type =
      projection_aggregator_type(kind, source) ||
        raise ArgumentError,
              "#{where} can't aggregate #{inspect(field)} with #{inspect(kind)}"

    Map.merge(
      %{"type" => type, "name" => name, "fieldName" => column},
      camelize_keys(opts)
    )
  end

  defp projection_aggregator(where, name, spec, _fields) do
    raise ArgumentError, "#{where} has an unknown aggregation #{name}: #{inspect(spec)}"
  end

  defp projection_aggregator_type(kind, source) when kind in [:sum, :min, :max, :first, :last] do
    prefix =
      case source do
        {:dimension, %{type: "long"}} -> "long"
        {:dimension, %{type: type}} when type in ["double", "float"] -> "double"
        {:dimension, %{type: "string"}} when kind in [:first, :last] -> "string"
        {:metric, %{type: "count"}} -> "long"
        {:metric, %{type: "long" <> _}} -> "long"
        {:metric, %{type: "double" <> _}} -> "double"
        {:metric, %{type: "float" <> _}} -> "double"
        _ -> nil
      end

    if prefix, do: prefix <> (kind |> Atom.to_string() |> String.capitalize())
  end

  defp projection_aggregator_type(kind, source) when is_map_key(@complex_aggregators, kind) do
    {build, merge} = Map.fetch!(@complex_aggregators, kind)

    case source do
      {:dimension, _} -> build
      {:metric, _} -> merge
    end
  end

  defp projection_aggregator_type(kind, _source) when is_binary(kind), do: kind
  defp projection_aggregator_type(_kind, _source), do: nil

  defp column(name, ecto_opts) do
    ecto_opts |> Keyword.get(:source, name) |> to_string()
  end

  defp camelize_keys(opts) do
    Map.new(opts, fn
      {key, value} when is_atom(key) -> {camelize(Atom.to_string(key)), value}
      {key, value} when is_binary(key) -> {key, value}
    end)
  end

  defp camelize(key) do
    [first | rest] = String.split(key, "_")
    Enum.join([first | Enum.map(rest, &String.capitalize/1)])
  end
end
