defmodule Ecto.Druid.Query.Table do
  @moduledoc """
  Druid table functions for use in FROM and JOIN clauses.
  """
  import Ecto.Druid.Util, only: [sql_function: 1]

  @doc """
  Druid TABLE function. Wraps an input source such as `extern/3` for use as a
  query source.

      from(e in table(extern(input_source, input_format, row_signature)))
  """
  sql_function table(source)

  @doc """
  Reads external data, for use with SQL-based ingestion. Takes the JSON-encoded
  input source, input format, and row signature.
  """
  sql_function extern(input_source, input_format, row_signature)

  @doc """
  Reads several data sources as one, for use with `table/1`. Columns are
  matched by name; a column a data source lacks is `NULL` in its rows, so the
  data sources don't need the same columns.

      from(e in table(append(["edits", "edits_backfill"])),
        group_by: e.channel,
        select: {e.channel, count()}
      )

  The names can also be pinned at runtime with `splice/1`:

      from(e in table(append(splice(^data_sources))), select: count())
  """
  sql_function append(data_sources)

  @doc """
  Unnests an ARRAY or multi-value column into rows. Use as a join source, with
  the column alias(es) given as an atom or list of atoms:

      from(t in "test", cross_join: u in unnest(t.tags, :tag), select: u.tag)

  Generates `CROSS JOIN UNNEST(t0."tags") AS f1 ("tag")`, with the unnested
  value available as `u.tag`.
  """
  defmacro unnest(arr, cols) when is_atom(cols) or is_list(cols) do
    cols =
      cols
      |> List.wrap()
      |> Enum.map_join(", ", &~s("#{&1}"))

    Ecto.Druid.Util.sql_function_body("UNNEST", "?", [arr], nil, {"(", ") AS (#{cols})"})
  end
end
