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
        only: [timestamp: 1, timestamp: 2, dimension: 2, dimension: 3, metric: 2, metric: 3]

      Module.register_attribute(__MODULE__, :druid_timestamp, accumulate: true)
      Module.register_attribute(__MODULE__, :druid_dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :druid_metrics, accumulate: true)

      @before_compile Ecto.Druid.Schema
    end
  end

  @doc """
  Defines the `__time` column as field `name`, of type `Ecto.Druid.DateTime`.

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
      Ecto.Schema.field(name, Ecto.Druid.DateTime, Keyword.put(ecto_opts, :source, :__time))
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

    quote do
      @doc false
      def __druid__(:timestamp), do: unquote(Macro.escape(timestamp))
      def __druid__(:dimensions), do: unquote(Macro.escape(dimensions))
      def __druid__(:metrics), do: unquote(Macro.escape(metrics))
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
