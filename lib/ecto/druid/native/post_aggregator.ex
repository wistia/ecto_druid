defmodule Ecto.Druid.Native.PostAggregator do
  @moduledoc """
  Builds [native query post-aggregators](https://druid.apache.org/docs/latest/querying/post-aggregations),
  which compute values from the aggregated results.

      import Ecto.Druid.Native.PostAggregator
      import Ecto.Druid.Native.Expression

      [
        arithmetic("robot_share", :/, ["robot_edits", "edits"]),
        expression("net", expr(added - deleted))
      ]

  Each function returns the post-aggregator as a plain map.
  """

  alias Ecto.Druid.Native.Aggregator
  alias Ecto.Druid.Native.Expression

  @type t :: map()

  @doc """
  Computes a Druid expression over the aggregated results.

  ## Options

    * `:output_type` - The type of the result, such as `"DOUBLE"`.

  ## Examples

      iex> import Ecto.Druid.Native.Expression
      iex> Ecto.Druid.Native.PostAggregator.expression("net", expr(added - deleted))
      %{type: "expression", name: "net", expression: expr(added - deleted)}
  """
  @spec expression(String.t() | atom(), Expression.t() | String.t(), Keyword.t()) :: t()
  def expression(name, expression, opts \\ []) do
    %{type: "expression", name: name, expression: expression}
    |> Map.merge(Aggregator.camelize(opts))
  end

  @doc """
  Applies an arithmetic function (`+`, `-`, `*`, `/` or `quotient`) to
  `fields`, in order. A field given as a name reads that aggregator, as with
  `field_access/2`.

  ## Options

    * `:ordering` - `"numericFirst"` to order the results with finite values
      first.

  ## Examples

      iex> Ecto.Druid.Native.PostAggregator.arithmetic("half", :/, ["edits", 2])
      %{type: "arithmetic", name: "half", fn: "/",
        fields: [%{type: "fieldAccess", fieldName: "edits"}, %{type: "constant", value: 2}]}
  """
  @spec arithmetic(
          String.t() | atom(),
          atom() | String.t(),
          [t() | String.t() | atom() | number()],
          Keyword.t()
        ) ::
          t()
  def arithmetic(name, function, fields, opts \\ []) do
    %{type: "arithmetic", name: name, fn: to_string(function), fields: Enum.map(fields, &field/1)}
    |> Map.merge(Aggregator.camelize(opts))
  end

  @doc """
  Reads the result of the aggregator named `field`. Pass `finalize: true` to
  read the finalized value, such as a sketch's estimate rather than the
  sketch.

  ## Options

    * `:name` - The output name, when used as a post-aggregator on its own.
    * `:finalize` - Whether to read the finalized value.

  ## Examples

      iex> Ecto.Druid.Native.PostAggregator.field_access("users", finalize: true)
      %{type: "finalizingFieldAccess", fieldName: "users"}
  """
  @spec field_access(String.t() | atom(), Keyword.t()) :: t()
  def field_access(field, opts \\ []) do
    type = if opts[:finalize], do: "finalizingFieldAccess", else: "fieldAccess"
    Ecto.Druid.Native.Filter.put_present(%{type: type, fieldName: field}, :name, opts[:name])
  end

  @doc """
  A constant value.

      iex> Ecto.Druid.Native.PostAggregator.constant(100)
      %{type: "constant", value: 100}
  """
  @spec constant(number(), Keyword.t()) :: t()
  def constant(value, opts \\ []) when is_number(value) do
    Ecto.Druid.Native.Filter.put_present(%{type: "constant", value: value}, :name, opts[:name])
  end

  defp field(field) when is_binary(field) or is_atom(field), do: field_access(field)
  defp field(value) when is_number(value), do: constant(value)
  defp field(post_aggregator) when is_map(post_aggregator), do: post_aggregator
end
