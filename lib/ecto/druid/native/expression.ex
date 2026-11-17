defmodule Ecto.Druid.Native.Expression do
  @moduledoc """
  Writes [Druid expressions](https://druid.apache.org/docs/latest/querying/math-expr)
  in Elixir syntax, for the places a native query takes one: expression
  virtual columns, filters, aggregators and post-aggregators.

      import Ecto.Druid.Native.Expression

      expr(if(deleted > 0, cast(added, "DOUBLE") / deleted, 0.0))
      #=> #Ecto.Druid.Native.Expression<if(("deleted" > 0), (cast("added", 'DOUBLE') / "deleted"), 0.0)>

  `expr/1` takes care of quoting, so a column or string can't break out of its
  place in the expression. It returns an `Ecto.Druid.Native.Expression`, which
  encodes to JSON as the expression string, so you can put it straight into a
  query map.
  """

  @enforce_keys [:expression]
  defstruct [:expression]

  @type t :: %__MODULE__{expression: String.t()}

  @binary_ops %{
    +: "+",
    -: "-",
    *: "*",
    /: "/",
    **: "^",
    ==: "==",
    !=: "!=",
    <: "<",
    <=: "<=",
    >: ">",
    >=: ">=",
    and: "&&",
    &&: "&&",
    or: "||",
    ||: "||"
  }

  @doc """
  Builds a Druid expression from Elixir syntax.

    * Variables are columns: `added` is `"added"`. Use `^column(name)` for a
      column whose name is only known at runtime, or isn't a valid Elixir
      variable name.
    * Strings, numbers, `nil`, booleans and lists of them are literals.
      Druid has no booleans, so `true` and `false` are `1` and `0`.
    * `^value` interpolates an Elixir value as a literal, or, for an
      `Ecto.Druid.Native.Expression`, as a subexpression. Sigils, such as
      `~U[2016-06-27 00:00:00Z]`, are interpolated the same way, and a
      `DateTime` becomes epoch milliseconds, to compare with `__time`.
    * Function calls are Druid functions: `nvl(user, "anonymous")`,
      `timestamp_floor(__time, "PT1H")`. They can be piped, as in
      `user |> nvl("anonymous") |> upper()`. `if` works with either
      `if(cond, a, b)` or `if cond, do: a, else: b`.
    * Operators: `+`, `-`, `*`, `/`, `**` (Druid's `^`), `rem/2` (`%`), the
      comparisons, `and`/`&&`, `or`/`||`, `not`/`!` and unary `-`.

  ## Examples

      iex> import Ecto.Druid.Native.Expression
      iex> to_string(expr(nvl(added, 0) * 2))
      ~S|(nvl("added", 0) * 2)|

      iex> import Ecto.Druid.Native.Expression
      iex> channel = "#en.wikipedia"
      iex> to_string(expr(channel == ^channel and not isRobot))
      ~S|(("channel" == '#en.wikipedia') && !"isRobot")|

      iex> import Ecto.Druid.Native.Expression
      iex> rate = expr(cast(added, "DOUBLE") / delta)
      iex> to_string(expr(^rate |> round(2)))
      ~S|round((cast("added", 'DOUBLE') / "delta"), 2)|
  """
  defmacro expr(ast) do
    quote do
      %Ecto.Druid.Native.Expression{
        expression: IO.iodata_to_binary(unquote(compile(ast)))
      }
    end
  end

  @doc """
  A column whose name is only known at runtime, to interpolate into `expr/1`
  with `^`.

      iex> import Ecto.Druid.Native.Expression
      iex> name = "page-name"
      iex> to_string(expr(concat(^column(name), "!")))
      ~S|concat("page-name", '!')|
  """
  @spec column(String.t() | atom()) :: t()
  def column(name), do: %__MODULE__{expression: identifier(name)}

  @doc """
  Encodes an Elixir value as a Druid expression literal.

      iex> Ecto.Druid.Native.Expression.literal("it's")
      ~S|'it\\'s'|

      iex> Ecto.Druid.Native.Expression.literal([1, 2.5, nil])
      "[1, 2.5, null]"
  """
  @spec literal(term()) :: String.t()
  def literal(nil), do: "null"
  def literal(true), do: "1"
  def literal(false), do: "0"
  def literal(value) when is_integer(value), do: Integer.to_string(value)
  def literal(value) when is_float(value), do: Float.to_string(value)

  def literal(value) when is_binary(value),
    do: "'" <> String.replace(value, ~r/['\\]/, "\\\\\\0") <> "'"

  def literal(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ", ", &literal/1) <> "]"

  def literal(%DateTime{} = value), do: value |> DateTime.to_unix(:millisecond) |> literal()

  def literal(value) do
    raise ArgumentError,
          "#{inspect(value)} can't be written as a Druid expression literal"
  end

  @doc false
  def identifier(name),
    do: ~s(") <> String.replace(to_string(name), ~r/["\\]/, "\\\\\\0") <> ~s(")

  @doc false
  def __pin__(%__MODULE__{expression: expression}), do: expression
  def __pin__(value), do: literal(value)

  # Compiles to quoted code that builds the expression as iodata, so literal
  # parts are encoded at compile time and only pinned values at runtime.

  defp compile({:^, _, [value]}) do
    quote do: Ecto.Druid.Native.Expression.__pin__(unquote(value))
  end

  defp compile({name, _, context}) when is_atom(name) and is_atom(context),
    do: identifier(name)

  defp compile({op, _, [left, right]}) when is_map_key(@binary_ops, op) do
    ["(", compile(left), " ", @binary_ops[op], " ", compile(right), ")"]
  end

  defp compile({:|>, _, _} = ast) do
    [{call, _} | rest] = Macro.unpipe(ast)

    rest
    |> Enum.reduce(call, fn {ast, position}, acc -> Macro.pipe(acc, ast, position) end)
    |> compile()
  end

  defp compile({:rem, _, [left, right]}), do: ["(", compile(left), " % ", compile(right), ")"]
  defp compile({:-, _, [value]}), do: ["-", compile(value)]
  defp compile({op, _, [value]}) when op in [:not, :!], do: ["!", compile(value)]

  defp compile({:if, meta, [condition, [do: then, else: otherwise]]}),
    do: compile({:if, meta, [condition, then, otherwise]})

  defp compile({:<>, _, _}),
    do: raise(ArgumentError, "<> isn't supported in a Druid expression. Use concat/2")

  defp compile({name, _, args} = ast) when is_atom(name) and is_list(args) do
    if String.starts_with?(Atom.to_string(name), "sigil_"),
      do: compile({:^, [], [ast]}),
      else: compile_call(name, args)
  end

  defp compile(value) when is_atom(value) and value not in [nil, true, false],
    do: identifier(value)

  defp compile(value) when is_list(value) do
    if Enum.all?(value, &literal?/1) do
      literal(value)
    else
      raise ArgumentError,
            "a list in a Druid expression must hold only literals, got: #{Macro.to_string(value)}. " <>
              "Use array/N to build one from columns or expressions"
    end
  end

  defp compile(value) do
    if literal?(value) do
      literal(value)
    else
      raise ArgumentError, "can't write #{Macro.to_string(value)} as a Druid expression"
    end
  end

  defp compile_call(name, args) do
    [Atom.to_string(name), "(", args |> Enum.map(&compile/1) |> Enum.intersperse(", "), ")"]
  end

  defp literal?(value),
    do: is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value)

  defimpl String.Chars do
    def to_string(%{expression: expression}), do: expression
  end

  defimpl Jason.Encoder do
    def encode(%{expression: expression}, opts), do: Jason.Encode.string(expression, opts)
  end

  defimpl Inspect do
    def inspect(%{expression: expression}, _opts),
      do: "#Ecto.Druid.Native.Expression<#{expression}>"
  end
end
