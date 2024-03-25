defmodule Ecto.Druid.Util do
  @moduledoc """
  Utility functions to generate SQL fragments.
  """

  @doc """
  Defines a SQL function that can be used in queries.

  ## Example

      defmodule MyApp.Query do
        import Ecto.Druid.Util

        sql_function :my_function, [:arg1, :arg2], type: :integer
      end

  Look at `Ecto.Druid.Query`'s source for more examples.
  """
  defmacro sql_function({name, _, args}, opts \\ []) do
    Ecto.Druid.Util.sql_function(name, args, opts)
  end

  @doc false
  def sql_function(name, args, opts) do
    fun = name |> Atom.to_string() |> String.upcase()
    type = Keyword.get(opts, :type, nil)
    placeholders = Keyword.get(opts, :placeholders, nil)
    wrapper = Keyword.get(opts, :wrapper, {"(", ")"})

    types =
      args
      |> Enum.map(fn _ ->
        quote do: Macro.t()
      end)

    quote do
      @spec unquote(name)(unquote_splicing(types)) :: Macro.t()
      defmacro unquote(name)(unquote_splicing(args)) do
        Ecto.Druid.Util.sql_function_body(
          unquote(fun),
          unquote(placeholders),
          unquote(args),
          unquote(type),
          unquote(wrapper)
        )
      end
    end
  end

  @doc """
  Defines a SQL function body that can be used in queries.

  ## Example

      defmodule MyApp.Query do
        defmacro my_function(arg1, arg2) do
          Ecto.Druid.Util.sql_function_body("MY_FUNCTION", "?, ?", [arg1, arg2])
        end
      end

  Look at `Ecto.Druid.Query`'s source for more examples.
  """
  def sql_function_body(fun, placeholders, args, type \\ nil, wrapper \\ {"(", ")"})

  def sql_function_body(fun, nil, args, type, wrapper) do
    placeholders = args |> List.flatten() |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")

    sql_function_body(fun, placeholders, args, type, wrapper)
  end

  def sql_function_body(fun, placeholders, args, type, {start, stop}) do
    args = args |> List.flatten()

    fragment = "#{fun}#{start}#{placeholders}#{stop}"
    fragment(fragment, args, type)
  end

  @doc false
  def fragment(fragment, args, nil) do
    {:fragment, [], [fragment | args]}
  end

  def fragment(fragment, args, type) do
    {:type, [], [fragment(fragment, args, nil), type]}
  end
end
