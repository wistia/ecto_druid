defmodule Ecto.Adapters.Druid.PostProcessor do
  def process_result([_header, types | rows]) do
    complex_indices =
      types
      |> Enum.with_index()
      |> Enum.filter(fn {type, _} -> String.starts_with?(type, "COMPLEX") end)
      |> Enum.map(&elem(&1, 1))

    if complex_indices == [] do
      rows
    else
      rows
      |> Enum.map(fn row ->
        row
        |> Enum.with_index()
        |> Enum.map(fn {value, index} ->
          if index in complex_indices do
            Jason.decode!(value)
          else
            value
          end
        end)
      end)
    end
  end
end
