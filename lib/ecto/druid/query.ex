defmodule Ecto.Druid.Query do
  defmacro extern_table(input_source, input_format, row_signature) do
    quote do
      fragment(
        "TABLE(EXTERN(?, ?, ?))",
        unquote(input_source),
        unquote(input_format),
        unquote(row_signature)
      )
    end
  end
end
