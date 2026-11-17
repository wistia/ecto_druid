defmodule Ecto.Druid.Native.Aggregator do
  @moduledoc """
  Builds [native query aggregators](https://druid.apache.org/docs/latest/querying/aggregations).

  Each function returns the aggregator as a plain map:

      import Ecto.Druid.Native.Aggregator
      import Ecto.Druid.Native.Expression

      [
        count("edits"),
        long_sum("added"),
        long_sum(expr(added - deleted), name: "net"),
        count("robot_edits") |> filtered(Ecto.Druid.Native.Filter.equals("isRobot", "true"))
      ]

  The first argument is the column to aggregate, which also names the output.
  Pass an `Ecto.Druid.Native.Expression` instead to aggregate an expression,
  along with a `:name`.

  ## Options

  Every aggregator takes:

    * `:name` - The output name. Defaults to the column.
    * `:filter` - Only aggregate the rows that match this filter, by wrapping
      the aggregator in a `filtered` one.

  Any other option is added to the aggregator with its key in camelCase, so
  `max_string_bytes: 1024` becomes `maxStringBytes: 1024`.
  """

  alias Ecto.Druid.Native.Expression

  @type t :: map()
  @type field :: String.t() | atom() | Expression.t()

  @doc """
  Counts the rows.

      iex> Ecto.Druid.Native.Aggregator.count("edits")
      %{type: "count", name: "edits"}
  """
  @spec count(String.t() | atom(), Keyword.t()) :: t()
  def count(name, opts \\ []) do
    {filter, opts} = Keyword.pop(opts, :filter)
    %{type: "count", name: name} |> Map.merge(camelize(opts)) |> wrap(filter)
  end

  for type <- ~w(long double float), op <- ~w(sum min max first last any) do
    name = :"#{type}_#{op}"
    druid_type = type <> String.capitalize(op)

    @doc """
    Builds a `#{druid_type}` aggregator.

        iex> Ecto.Druid.Native.Aggregator.#{name}("added")
        %{type: "#{druid_type}", name: "added", fieldName: "added"}
    """
    @spec unquote(name)(field(), Keyword.t()) :: t()
    def unquote(name)(field, opts \\ []), do: aggregator(unquote(druid_type), field, opts)
  end

  for op <- ~w(first last any) do
    name = :"string_#{op}"
    druid_type = "string" <> String.capitalize(op)

    @doc """
    Builds a `#{druid_type}` aggregator. Takes `:max_string_bytes`.

        iex> Ecto.Druid.Native.Aggregator.#{name}("page")
        %{type: "#{druid_type}", name: "page", fieldName: "page"}
    """
    @spec unquote(name)(field(), Keyword.t()) :: t()
    def unquote(name)(field, opts \\ []), do: aggregator(unquote(druid_type), field, opts)
  end

  @doc """
  Builds a `thetaSketch` aggregator, from the
  [DataSketches extension](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-theta).
  Takes `:size` and `:is_input_theta_sketch`.

      iex> Ecto.Druid.Native.Aggregator.theta_sketch("user", name: "users", size: 16384)
      %{type: "thetaSketch", name: "users", fieldName: "user", size: 16384}
  """
  @spec theta_sketch(field(), Keyword.t()) :: t()
  def theta_sketch(field, opts \\ []), do: aggregator("thetaSketch", field, opts)

  @doc """
  Builds an `HLLSketchBuild` aggregator, or an `HLLSketchMerge` one with
  `merge: true` for a column that already holds sketches. From the
  [DataSketches extension](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-hll).
  Takes `:lg_k` and `:tgt_hll_type`.

      iex> Ecto.Druid.Native.Aggregator.hll_sketch("user", name: "users", lg_k: 12)
      %{type: "HLLSketchBuild", name: "users", fieldName: "user", lgK: 12}
  """
  @spec hll_sketch(field(), Keyword.t()) :: t()
  def hll_sketch(field, opts \\ []) do
    {merge, opts} = Keyword.pop(opts, :merge, false)
    aggregator(if(merge, do: "HLLSketchMerge", else: "HLLSketchBuild"), field, opts)
  end

  @doc """
  Builds a `quantilesDoublesSketch` aggregator, from the
  [DataSketches extension](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-quantiles).
  Takes `:k`.

      iex> Ecto.Druid.Native.Aggregator.quantiles_doubles_sketch("added", k: 128)
      %{type: "quantilesDoublesSketch", name: "added", fieldName: "added", k: 128}
  """
  @spec quantiles_doubles_sketch(field(), Keyword.t()) :: t()
  def quantiles_doubles_sketch(field, opts \\ []),
    do: aggregator("quantilesDoublesSketch", field, opts)

  @doc """
  Wraps `aggregator` so it only aggregates the rows that match `filter`. The
  `:filter` option on the other aggregators does the same. A `nil` filter
  returns the aggregator as is.

      iex> import Ecto.Druid.Native.Aggregator
      iex> count("anonymous") |> filtered(Ecto.Druid.Native.Filter.null("user"))
      %{type: "filtered", filter: %{type: "null", column: "user"}, aggregator: %{type: "count", name: "anonymous"}}
  """
  @spec filtered(t(), map() | nil) :: t()
  def filtered(aggregator, nil), do: aggregator

  def filtered(aggregator, filter),
    do: %{type: "filtered", filter: filter, aggregator: aggregator}

  defp aggregator(type, field, opts) do
    {filter, opts} = Keyword.pop(opts, :filter)
    {name, opts} = Keyword.pop_lazy(opts, :name, fn -> default_name!(field) end)

    %{type: type, name: name}
    |> Map.merge(source(field))
    |> Map.merge(camelize(opts))
    |> wrap(filter)
  end

  defp source(%Expression{} = expression), do: %{expression: expression}
  defp source(field), do: %{fieldName: field}

  defp default_name!(%Expression{} = expression) do
    raise ArgumentError,
          "an aggregator of the expression #{expression} needs a :name"
  end

  defp default_name!(field), do: field

  defp wrap(aggregator, filter), do: filtered(aggregator, filter)

  @doc false
  def camelize(opts) do
    Map.new(opts, fn {key, value} ->
      <<first::utf8, rest::binary>> = key |> Atom.to_string() |> Macro.camelize()
      {String.to_atom(String.downcase(<<first::utf8>>) <> rest), value}
    end)
  end
end
