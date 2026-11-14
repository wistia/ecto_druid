defmodule Ecto.Druid.Query.JSON do
  @moduledoc """
  Druid [JSON functions](https://druid.apache.org/docs/latest/querying/sql-json-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]
  @doc "Returns an array of field names from expr at the specified path."
  sql_function json_keys(expr, path)

  @doc "Constructs a new COMPLEX<json> object. The KEY expressions must evaluate to string types. The VALUE expressions can be composed of any input type, including other COMPLEX<json> values. JSON_OBJECT can accept colon-separated key-value pairs. The following syntax is equivalent: JSON_OBJECT(expr1:expr2[, expr3:expr4, ...])."
  defmacro json_object(kv_pairs) do
    placeholders = kv_pairs |> Enum.map(fn _ -> "KEY ? VALUE ?" end) |> Enum.join(", ")
    args = kv_pairs |> Enum.flat_map(fn {k, v} -> [to_string(k), v] end)

    Ecto.Druid.Util.sql_function_body(
      "JSON_OBJECT",
      placeholders,
      args
    )
  end

  @doc "Returns an array of all paths which refer to literal values in expr in JSONPath format."
  sql_function json_paths(expr)

  @doc "Extracts a COMPLEX<json> value from expr, at the specified path."
  sql_function json_query(expr, path)

  @doc "Extracts an ARRAY<COMPLEX<json>> value from expr at the specified path. If value is not an ARRAY, it gets translated into a single element ARRAY containing the value at path. The primary use of this function is to extract arrays of objects to use as inputs to other array functions."
  sql_function json_query_array(expr, path)

  @doc "Extracts a literal value from expr at the specified path. If you specify RETURNING and an SQL type name (such as VARCHAR, BIGINT, DOUBLE, etc) the function plans the query using the suggested type. Otherwise, it attempts to infer the type based on the context. If it can't infer the type, it defaults to VARCHAR."
  sql_function json_value(expr, path)

  @doc "Extracts a literal value from expr at the specified path. If you specify RETURNING and an SQL type name (such as VARCHAR, BIGINT, DOUBLE, etc) the function plans the query using the suggested type. Otherwise, it attempts to infer the type based on the context. If it can't infer the type, it defaults to VARCHAR."
  sql_function json_value(expr, path, type), placeholders: "?, ? RETURNING ?"

  @doc "Parses expr into a COMPLEX<json> object. This operator deserializes JSON values when processing them, translating stringified JSON into a nested structure. If the input is not a VARCHAR or it is invalid JSON, this function will result in an error."
  sql_function parse_json(expr)

  @doc "Parses expr into a COMPLEX<json> object. This operator deserializes JSON values when processing them, translating stringified JSON into a nested structure. If the input is not a VARCHAR or it is invalid JSON, this function will result in a NULL value."
  sql_function try_parse_json(expr)

  @doc "Serializes expr into a JSON string."
  sql_function to_json_string(expr)

  @doc "Merges two or more JSON expressions into one, preserving the rightmost value when keys overlap. Pass the expressions as a list of at least two elements. Returns a COMPLEX<json> object."
  sql_function json_merge(exprs)
end
