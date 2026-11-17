defmodule Ecto.Druid.Native.Filter do
  @moduledoc """
  Builds [native query filters](https://druid.apache.org/docs/latest/querying/filters).

  Each function returns the filter as a plain map, so builders and
  hand-written filters mix freely:

      import Ecto.Druid.Native.Filter

      and_([
        equals("channel", "#en.wikipedia"),
        range("added", lower: 10),
        null("user") |> not_()
      ])

  The match value type that `equals/3` and `range/2` need is worked out from
  the value: `"STRING"` for strings, `"LONG"` for integers and `DateTime`s
  (as epoch milliseconds, for `__time`), `"DOUBLE"` for floats, and
  `"ARRAY<...>"` for lists. Pass `:type` to set it yourself.

  The functions whose names clash with Elixir's operators end in an
  underscore: `and_/1`, `or_/1`, `not_/1` and `in_/2`.
  """

  alias Ecto.Druid.Native.Expression

  @type t :: map()
  @type column :: String.t() | atom()

  @doc """
  Matches rows where `column` equals `value`.

  ## Options

    * `:type` - The match value type, such as `"STRING"` or `"LONG"`.

  ## Examples

      iex> Ecto.Druid.Native.Filter.equals("channel", "#en.wikipedia")
      %{type: "equals", column: "channel", matchValueType: "STRING", matchValue: "#en.wikipedia"}

      iex> Ecto.Druid.Native.Filter.equals("tags", ["a", "b"])
      %{type: "equals", column: "tags", matchValueType: "ARRAY<STRING>", matchValue: ["a", "b"]}
  """
  @spec equals(column(), term(), Keyword.t()) :: t()
  def equals(column, value, opts \\ []) do
    %{
      type: "equals",
      column: column,
      matchValueType: Keyword.get_lazy(opts, :type, fn -> type_of!(value) end),
      matchValue: match_value(value)
    }
  end

  @doc """
  Matches rows where `column` is null.

      iex> Ecto.Druid.Native.Filter.null("user")
      %{type: "null", column: "user"}
  """
  @spec null(column()) :: t()
  def null(column), do: %{type: "null", column: column}

  @doc """
  Matches rows where `column` is one of `values`.

      iex> Ecto.Druid.Native.Filter.in_("channel", ["#en.wikipedia", "#de.wikipedia"])
      %{type: "in", dimension: "channel", values: ["#en.wikipedia", "#de.wikipedia"]}
  """
  @spec in_(column(), [term()]) :: t()
  def in_(column, values) when is_list(values),
    do: %{type: "in", dimension: column, values: values}

  @doc """
  Matches rows where `column` is in a range. Both bounds are inclusive unless
  marked open, and either can be left out.

  ## Options

    * `:lower` - The lower bound.
    * `:upper` - The upper bound.
    * `:lower_open` - Whether to leave out rows equal to `:lower`.
    * `:upper_open` - Whether to leave out rows equal to `:upper`.
    * `:type` - The match value type. Worked out from the bounds by default.

  ## Examples

      iex> Ecto.Druid.Native.Filter.range("added", lower: 10, upper: 100, upper_open: true)
      %{type: "range", column: "added", matchValueType: "LONG", lower: 10, upper: 100, upperOpen: true}

      iex> Ecto.Druid.Native.Filter.range("__time", lower: ~U[2016-06-27 00:00:00Z])
      %{type: "range", column: "__time", matchValueType: "LONG", lower: 1466985600000}
  """
  @spec range(column(), Keyword.t()) :: t()
  def range(column, opts) do
    bounds = Keyword.take(opts, [:lower, :upper])

    if bounds == [] do
      raise ArgumentError, "range/2 needs a :lower or :upper bound"
    end

    type =
      Keyword.get_lazy(opts, :type, fn ->
        case bounds |> Keyword.values() |> Enum.map(&type_of!/1) |> Enum.uniq() do
          [type] -> type
          types -> if Enum.sort(types) == ["DOUBLE", "LONG"], do: "DOUBLE", else: mixed!(bounds)
        end
      end)

    %{type: "range", column: column, matchValueType: type}
    |> put_present(:lower, match_value(opts[:lower]))
    |> put_present(:upper, match_value(opts[:upper]))
    |> put_present(:lowerOpen, opts[:lower_open])
    |> put_present(:upperOpen, opts[:upper_open])
  end

  @doc """
  Matches rows where `column` matches a SQL `LIKE` pattern, where `%` matches
  any characters and `_` matches one.

  ## Options

    * `:escape` - A character that makes the `%` or `_` after it match literally.

  ## Examples

      iex> Ecto.Druid.Native.Filter.like("page", "Black%")
      %{type: "like", dimension: "page", pattern: "Black%"}
  """
  @spec like(column(), String.t(), Keyword.t()) :: t()
  def like(column, pattern, opts \\ []) do
    put_present(%{type: "like", dimension: column, pattern: pattern}, :escape, opts[:escape])
  end

  @doc """
  Matches rows whose time is in one of `intervals`, given as
  `Ecto.Druid.Interval`s or ISO 8601 interval strings.

  ## Options

    * `:column` - The column to match. Defaults to `"__time"`.

  ## Examples

      iex> Ecto.Druid.Native.Filter.interval(["2016-06-27/2016-06-28"])
      %{type: "interval", dimension: "__time", intervals: ["2016-06-27/2016-06-28"]}
  """
  @spec interval([Ecto.Druid.Interval.t() | String.t()] | Ecto.Druid.Interval.t(), Keyword.t()) ::
          t()
  def interval(intervals, opts \\ []) do
    %{
      type: "interval",
      dimension: Keyword.get(opts, :column, "__time"),
      intervals: List.wrap(intervals)
    }
  end

  @doc """
  Matches rows where a Druid expression is true, written with
  `Ecto.Druid.Native.Expression.expr/1` or as a string.

      iex> import Ecto.Druid.Native.Expression
      iex> Ecto.Druid.Native.Filter.expression(expr(added > deleted * 2))
      %{type: "expression", expression: expr(added > deleted * 2)}
  """
  @spec expression(Expression.t() | String.t()) :: t()
  def expression(expression), do: %{type: "expression", expression: expression}

  @doc """
  Matches rows that match all of `filters`. `nil` filters are left out, so
  optional filters can be written inline, and a single filter is returned as
  is. With no filters left, returns `nil`, which matches every row.

      iex> import Ecto.Druid.Native.Filter
      iex> and_([null("user"), nil])
      %{type: "null", column: "user"}
  """
  @spec and_([t() | nil]) :: t() | nil
  def and_(filters), do: logical("and", filters)

  @doc """
  Matches rows that match any of `filters`. `nil` filters are left out, as
  with `and_/1`.
  """
  @spec or_([t() | nil]) :: t() | nil
  def or_(filters), do: logical("or", filters)

  @doc """
  Matches rows that don't match `filter`.

      iex> import Ecto.Druid.Native.Filter
      iex> null("user") |> not_()
      %{type: "not", field: %{type: "null", column: "user"}}
  """
  @spec not_(t() | nil) :: t() | nil
  def not_(nil), do: nil
  def not_(filter), do: %{type: "not", field: filter}

  defp logical(type, filters) when is_list(filters) do
    case Enum.reject(filters, &is_nil/1) do
      [] -> nil
      [filter] -> filter
      filters -> %{type: type, fields: filters}
    end
  end

  @doc false
  def type_of!(value) when is_binary(value), do: "STRING"
  def type_of!(value) when is_integer(value), do: "LONG"
  def type_of!(value) when is_float(value), do: "DOUBLE"
  def type_of!(%DateTime{}), do: "LONG"

  def type_of!([_ | _] = values) do
    case values |> Enum.map(&type_of!/1) |> Enum.uniq() do
      [type] ->
        "ARRAY<#{type}>"

      _ ->
        raise ArgumentError,
              "can't work out a match value type for #{inspect(values)}. Pass :type"
    end
  end

  def type_of!(value) do
    raise ArgumentError, "can't work out a match value type for #{inspect(value)}. Pass :type"
  end

  defp mixed!(bounds) do
    raise ArgumentError,
          "the bounds #{inspect(bounds)} have different types. Pass :type"
  end

  defp match_value(%DateTime{} = value), do: DateTime.to_unix(value, :millisecond)
  defp match_value(values) when is_list(values), do: Enum.map(values, &match_value/1)
  defp match_value(value), do: value

  @doc false
  def put_present(map, _key, nil), do: map
  def put_present(map, key, value), do: Map.put(map, key, value)
end
