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

  ## Legacy filters

  `equals/3`, `null/1` and `range/2` build the filters Druid 27 added, which
  its SQL planner uses. For Druid before 27, or queries written for it, use
  `selector/3` and `bound/2`. Druid still supports both. They differ from
  the newer filters in how they treat nulls:

    * `selector/3` with a `nil` value matches nulls. `equals/3` never matches
      nulls, so use `null/1` for that.
    * `bound/2` without a lower bound matches nulls. `range/2` never does.

  `bound/2` also compares with an ordering (`"lexicographic"`,
  `"alphanumeric"`, `"numeric"`, `"strlen"` or `"version"`) instead of a
  match value type.
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
  Builds a legacy `selector` filter, which matches rows where `dimension`
  equals `value`, or is null when `value` is `nil`. Druid compares the value
  as a string, coercing it for numeric columns. See
  [Legacy filters](#module-legacy-filters).

  ## Options

    * `:extraction_fn` - An extraction function to apply to the dimension
      before matching.

  ## Examples

      iex> Ecto.Druid.Native.Filter.selector("channel", "#en.wikipedia")
      %{type: "selector", dimension: "channel", value: "#en.wikipedia"}

      iex> Ecto.Druid.Native.Filter.selector("user", nil)
      %{type: "selector", dimension: "user", value: nil}
  """
  @spec selector(column(), term(), Keyword.t()) :: t()
  def selector(dimension, value, opts \\ []) do
    put_present(
      %{type: "selector", dimension: dimension, value: value},
      :extractionFn,
      opts[:extraction_fn]
    )
  end

  @doc """
  Builds a legacy `bound` filter, which matches rows where `dimension` is in
  a range. Both bounds are inclusive unless marked strict, and either can be
  left out. Without a lower bound, it also matches nulls. See
  [Legacy filters](#module-legacy-filters).

  ## Options

    * `:lower` - The lower bound.
    * `:upper` - The upper bound.
    * `:lower_strict` - Whether to leave out rows equal to `:lower`.
    * `:upper_strict` - Whether to leave out rows equal to `:upper`.
    * `:ordering` - How to compare values: `"lexicographic"`,
      `"alphanumeric"`, `"numeric"`, `"strlen"` or `"version"`. Defaults to
      `"numeric"` when the bounds are numbers, and to Druid's
      `"lexicographic"` otherwise.
    * `:extraction_fn` - An extraction function to apply to the dimension
      before comparing.

  ## Examples

      iex> Ecto.Druid.Native.Filter.bound("added", lower: 10, lower_strict: true)
      %{type: "bound", dimension: "added", lower: 10, lowerStrict: true, ordering: "numeric"}

      iex> Ecto.Druid.Native.Filter.bound("page", lower: "A", upper: "B", upper_strict: true)
      %{type: "bound", dimension: "page", lower: "A", upper: "B", upperStrict: true}
  """
  @spec bound(column(), Keyword.t()) :: t()
  def bound(dimension, opts) do
    bounds = opts |> Keyword.take([:lower, :upper]) |> Keyword.values()

    if bounds == [] do
      raise ArgumentError, "bound/2 needs a :lower or :upper bound"
    end

    ordering =
      Keyword.get_lazy(opts, :ordering, fn ->
        if Enum.all?(bounds, &is_number/1), do: "numeric"
      end)

    %{type: "bound", dimension: dimension}
    |> put_present(:lower, opts[:lower])
    |> put_present(:upper, opts[:upper])
    |> put_present(:lowerStrict, opts[:lower_strict])
    |> put_present(:upperStrict, opts[:upper_strict])
    |> put_present(:ordering, ordering)
    |> put_present(:extractionFn, opts[:extraction_fn])
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
