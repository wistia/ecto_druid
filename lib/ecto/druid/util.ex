defmodule Ecto.Druid.Util do
  defmacro sql_function({name, _, args}) do
    quote do
      defmacro unquote(name)(unquote_splicing(args)) do
        fun = unquote(name) |> Atom.to_string() |> String.upcase()
        args = [unquote_splicing(args)] |> List.flatten()
        placeholders = args |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")
        {:fragment, [], ["#{fun}(#{placeholders})" | args]}
      end
    end
  end
end
