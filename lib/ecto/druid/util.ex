defmodule Ecto.Druid.Util do
  defmacro sql_function({name, _, args}, opts \\ []) do
    type = Keyword.get(opts, :type, nil)

    if type do
      quote do
        defmacro unquote(name)(unquote_splicing(args)) do
          fun = unquote(name) |> Atom.to_string() |> String.upcase()
          args = unquote(args) |> List.flatten()
          placeholders = args |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")
          fragment = "#{fun}(#{placeholders})"
          type = unquote(type)

          {:type, [], [{:fragment, [], ["#{fun}(#{placeholders})" | args]}, type]}
        end
      end
    else
      quote do
        defmacro unquote(name)(unquote_splicing(args)) do
          fun = unquote(name) |> Atom.to_string() |> String.upcase()
          args = unquote(args) |> List.flatten()
          placeholders = args |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")
          fragment = "#{fun}(#{placeholders})"
          type = unquote(type)

          {:fragment, [], ["#{fun}(#{placeholders})" | args]}
        end
      end
    end
  end
end
