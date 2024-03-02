defmodule Seeds do
  import Ecto.Query
  import Ecto.Druid.Query

  @files [Path.join(["priv", "seeds", "conversion_events.csv"])]
  @columns [
    __time: "LONG",
    account_id: "LONG",
    page_id: "LONG",
    impressions: "LONG",
    conversions: "LONG"
  ]
  def conversion_events do
    local_file_seed(@files, @columns)
  end

  defp local_file_seed(files, columns) do
    column_names = Keyword.keys(columns)
    file_source = %{type: "local", files: files} |> Jason.encode!()
    file_format = %{type: "csv", findColumnsFromHeader: true} |> Jason.encode!()

    column_mappings =
      Enum.map(columns, &%{name: elem(&1, 0), type: elem(&1, 1)}) |> Jason.encode!()

    from(
      e in table(
        extern(
          ^file_source,
          ^file_format,
          ^column_mappings
        )
      ),
      select: ^column_names
    )
  end
end
