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

  defmacro approx_count_distinct_ds_theta(column, sketch_size) do
    quote do
      fragment(
        "APPROX_COUNT_DISTINCT_DS_THETA(?, ?)",
        unquote(column),
        unquote(sketch_size)
      )
    end
  end

  defmacro ds_quantiles_sketch(column, sketch_size) do
    quote do
      fragment(
        "DS_QUANTILES_SKETCH(?, ?)",
        unquote(column),
        unquote(sketch_size)
      )
    end
  end

  defmacro ds_histogram(column, split_points) do
    placeholders = split_points |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")

    {:fragment, [], ["DS_HISTOGRAM(?, #{placeholders})", column | split_points]}
  end
end
