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
  Reads external data, for use with SQL-based ingestion. Takes Druid's
  [input source](https://druid.apache.org/docs/latest/ingestion/input-sources),
  [input format](https://druid.apache.org/docs/latest/ingestion/data-formats)
  and row signature.

      input = %{type: "s3", uris: ["s3://my-bucket/page_views.csv"]}
      format = %{type: "csv", findColumnsFromHeader: true}

      from(e in table(extern(^input, ^format, ^[page: :string, views: :long])),
        select: %{page: e.page, views: e.views}
      )

  Maps and lists are encoded as JSON, and strings are sent as they are, so
  JSON you've already encoded works too. The row signature can be a keyword
  list of column names and types, as for `extend/2`, or Druid's own list of
  `%{name: ..., type: ...}` maps. Unlike `extend/2`, it can be built at
  runtime.
  """
  defmacro extern(input_source, input_format, row_signature) do
    args = [
      json_arg(input_source, :json, __CALLER__),
      json_arg(input_format, :json, __CALLER__),
      json_arg(row_signature, :signature, __CALLER__)
    ]

    Ecto.Druid.Util.sql_function_body("EXTERN", nil, args)
  end

  @doc """
  Reads external data, for use with SQL-based ingestion, with the columns
  given by `extend/2` instead of a row signature. Takes the input source and
  input format, as maps or JSON strings (see `extern/3`).

      from(e in extend(table(extern(^input_source, ^input_format)), page: :string, views: :long))
  """
  defmacro extern(input_source, input_format) do
    args = [
      json_arg(input_source, :json, __CALLER__),
      json_arg(input_format, :json, __CALLER__)
    ]

    Ecto.Druid.Util.sql_function_body("EXTERN", nil, args)
  end

  # Pinned values, and map or list literals, are encoded when the query is
  # built. Anything else, such as a string literal, goes into the query as is.
  defp json_arg(arg, kind, env) do
    case Macro.expand(arg, env) do
      {:^, meta, [value]} ->
        {:^, meta, [quote(do: Ecto.Druid.Query.Table.__json__(unquote(value), unquote(kind)))]}

      value when is_list(value) or (is_tuple(value) and elem(value, 0) == :%{}) ->
        {:^, [], [quote(do: Ecto.Druid.Query.Table.__json__(unquote(value), unquote(kind)))]}

      _ ->
        arg
    end
  end

  @doc false
  def __json__(value, _kind) when is_binary(value), do: value

  def __json__([{name, _} | _] = columns, :signature) when is_atom(name) do
    columns
    |> Enum.map(fn {name, type} -> %{name: name, type: signature_type(type)} end)
    |> Jason.encode!()
  end

  def __json__(value, _kind), do: Jason.encode!(value)

  @doc """
  Declares the columns of an `extern/2` source, as Druid's `EXTEND` clause.
  Takes a keyword list of column names and types, which must be known at
  compile time: a literal or a module attribute.

      from(e in extend(table(extern(^input_source, ^input_format)),
               ts: :string,
               page: :string,
               views: :long,
               tags: {:array, :string}
             ),
        select: %{__time: time_parse(e.ts), page: e.page, views: e.views, tags: e.tags}
      )

  Generates `TABLE(EXTERN(?, ?)) EXTEND ("ts" VARCHAR, "page" VARCHAR, "views"
  BIGINT, "tags" VARCHAR ARRAY)`.

  The types are `:string`, `:long`, `:float`, `:double`, `:json` (nested
  JSON, as `COMPLEX<json>`), and `{:array, type}` of `:string`, `:long` or
  `:double`.
  """
  defmacro extend(source, columns) do
    columns = Macro.expand(columns, __CALLER__)

    unless Keyword.keyword?(columns) and columns != [] do
      raise ArgumentError,
            "extend/2 expects a non-empty keyword list of column names and types, " <>
              "known at compile time, got: #{Macro.to_string(columns)}"
    end

    columns =
      Enum.map_join(columns, ", ", fn {name, type} ->
        name = name |> Atom.to_string() |> String.replace(~s("), ~s(""))
        ~s("#{name}" #{extend_type(type)})
      end)

    Ecto.Druid.Util.sql_function_body("", "?", [source], nil, {"", " EXTEND (#{columns})"})
  end

  @scalar_types %{string: "VARCHAR", long: "BIGINT", float: "FLOAT", double: "DOUBLE"}
  @array_types [:string, :long, :double]

  defp extend_type(:json), do: "TYPE('COMPLEX<json>')"
  defp extend_type(type) when is_map_key(@scalar_types, type), do: @scalar_types[type]

  defp extend_type({:array, type}) when type in @array_types,
    do: "#{@scalar_types[type]} ARRAY"

  defp extend_type(type), do: unsupported_type!("extend/2", type)

  defp signature_type(:json), do: "COMPLEX<json>"
  defp signature_type(type) when is_map_key(@scalar_types, type), do: Atom.to_string(type)

  defp signature_type({:array, type}) when type in @array_types,
    do: "ARRAY<#{type |> Atom.to_string() |> String.upcase()}>"

  defp signature_type(type), do: unsupported_type!("extern/3", type)

  defp unsupported_type!(fun, type) do
    raise ArgumentError,
          "#{fun} doesn't support the column type #{inspect(type)}. Use :string, " <>
            ":long, :float, :double, :json, or {:array, type} of :string, :long or :double"
  end

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
