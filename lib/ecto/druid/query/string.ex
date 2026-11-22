defmodule Ecto.Druid.Query.String do
  @moduledoc """
  Druid string [scalar functions](https://druid.apache.org/docs/latest/querying/sql-scalar#string-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1, sql_function: 2]
  @doc "Concats a list of expressions."
  sql_function concat(exprs)
  @doc "Two argument version of CONCAT."
  sql_function textcat(expr1, expr2)
  @doc "Returns true if the str is a substring of expr."
  sql_function contains_string(expr, str)
  @doc "Returns true if the str is a substring of expr. The match is case-insensitive."
  sql_function icontains_string(expr, str)
  @doc "Decodes a Base64-encoded string into a UTF-8 encoded string."
  sql_function decode_base64_utf8(expr)
  @doc "Returns the leftmost length characters from expr."
  sql_function left(expr)
  @doc "Returns the leftmost length characters from expr."
  sql_function left(expr, length)
  @doc "Returns the rightmost length characters from expr."
  sql_function right(expr)
  @doc "Returns the rightmost length characters from expr."
  sql_function right(expr, length)
  @doc "Length of expr in UTF-16 code units."
  sql_function length_(expr)
  @doc "Alias for LENGTH."
  sql_function char_length(expr)
  @doc "Alias for LENGTH."
  sql_function character_length(expr)
  @doc "Alias for LENGTH."
  sql_function strlen(expr)

  @doc """
  Looks up `expr` in a registered query-time lookup, giving `NULL` for keys
  that are not in it.

  `lookup_name` is the lookup's name, or an `Ecto.Druid.Lookup` schema module:

      lookup(p.country, "countries")
      lookup(p.country, MyApp.Countries)

  Lookups can also be queried directly as tables; see `Ecto.Druid.Lookup`.
  """
  defmacro lookup(expr, lookup_name) do
    lookup_sql([expr, lookup_name(lookup_name, __CALLER__)])
  end

  @doc """
  Looks up `expr` in a registered query-time lookup, giving
  `replace_missing_value_with` for keys that are not in it.

      lookup(p.country, MyApp.Countries, "Unknown")

  See `lookup/2`.
  """
  defmacro lookup(expr, lookup_name, replace_missing_value_with) do
    lookup_sql([expr, lookup_name(lookup_name, __CALLER__), replace_missing_value_with])
  end

  defp lookup_sql(args), do: Ecto.Druid.Util.sql_function_body("LOOKUP", nil, args)

  # An alias for an Ecto.Druid.Lookup schema becomes that lookup's name, inlined
  # as a string literal. Anything else is passed through as the name.
  defp lookup_name({:__aliases__, _, _} = alias, caller) do
    module = Macro.expand(alias, caller)

    case Code.ensure_compiled(module) do
      {:module, module} ->
        if function_exported?(module, :__lookup__, 1) do
          module.__lookup__(:name)
        else
          raise ArgumentError,
                "#{inspect(module)} is not a lookup schema; define it with `use Ecto.Druid.Lookup`"
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not load lookup schema #{inspect(module)}: #{inspect(reason)}"
    end
  end

  defp lookup_name(name, _caller), do: name
  @doc "Returns expr in all lowercase."
  sql_function lower(expr)
  @doc "Returns expr in all uppercase."
  sql_function upper(expr)

  @doc "Returns a string of length from expr left-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function lpad(expr, length)

  @doc "Returns a string of length from expr left-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function lpad(expr, length, chars)

  @doc "Returns a string of length from expr right-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function rpad(expr, length)

  @doc "Returns a string of length from expr right-padded with chars. If length is shorter than the length of expr, the result is expr which is truncated to length. The result will be null if either expr or chars is null. If chars is an empty string, no padding is added, however expr may be trimmed if necessary."
  sql_function rpad(expr, length, chars)

  @doc "Parses a string into a long (BIGINT) with the given radix, or 10 (decimal) if a radix is not provided."
  sql_function parse_long(string)

  @doc "Parses a string into a long (BIGINT) with the given radix, or 10 (decimal) if a radix is not provided."
  sql_function parse_long(string, radix)

  @doc "Returns the index of needle within haystack, with indexes starting from 1. The search will begin at fromIndex, or 1 if fromIndex is not specified. If needle is not found, returns 0."
  sql_function position(needle, haystack), placeholders: "? IN ?"

  @doc "Returns the index of needle within haystack, with indexes starting from 1. The search will begin at fromIndex, or 1 if fromIndex is not specified. If needle is not found, returns 0."
  sql_function position(needle, haystack, from_index), placeholders: "? IN ? FROM ?"

  @doc "Apply regular expression pattern to expr and extract a capture group, or NULL if there is no match. If index is unspecified or zero, returns the first substring that matched the pattern. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern."
  sql_function regexp_extract(expr, pattern)

  @doc "Apply regular expression pattern to expr and extract a capture group, or NULL if there is no match. If index is unspecified or zero, returns the first substring that matched the pattern. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern."
  sql_function regexp_extract(expr, pattern, index)

  @doc "Returns whether expr matches regular expression pattern. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern. Similar to LIKE, but uses regexps instead of LIKE patterns. Especially useful in WHERE clauses."
  sql_function regexp_like(expr, pattern)

  @doc "Replaces all occurrences of regular expression pattern within expr with replacement. The replacement string may refer to capture groups using $1, $2, etc. The pattern may match anywhere inside expr; if you want to match the entire string instead, use the ^ and $ markers at the start and end of your pattern."
  sql_function regexp_replace(expr, pattern, replacement)
  @doc "Replaces pattern with replacement in expr, and returns the result."
  sql_function replace(expr, pattern, replacement)
  @doc "Repeats expr N times."
  sql_function repeat(expr, n)
  @doc "Reverses expr."
  sql_function reverse(expr)
  @doc "Returns a string formatted in the manner of Java's String.format."
  sql_function string_format(pattern, args)

  @doc "Returns the index of needle within haystack, with indexes starting from 1. If needle is not found, returns 0."
  sql_function strpos(haystack, needle)

  @doc "Returns a substring of expr starting at index, with a max length, both measured in UTF-16 code units."
  sql_function substring(expr, index)

  @doc "Returns a substring of expr starting at index, with a max length, both measured in UTF-16 code units."
  sql_function substring(expr, index, length)
  @doc "Alias for SUBSTRING."
  sql_function substr(expr, index)
  @doc "Alias for SUBSTRING."
  sql_function substr(expr, index, length)

  @doc "Returns expr with characters removed from the leading, trailing, or both ends of expr if they are in chars. If chars is not provided, it defaults to '' (a space). If the directional argument is not provided, it defaults to BOTH."
  sql_function trim(expr)

  @doc "Returns expr with characters removed from the leading, trailing, or both ends of expr if they are in chars. If chars is not provided, it defaults to '' (a space). If the directional argument is not provided, it defaults to BOTH."
  sql_function trim(chars, expr), placeholders: "? FROM ?"
  @doc "Alternate form of TRIM(BOTH chars FROM expr)."
  sql_function btrim(expr)
  @doc "Alternate form of TRIM(BOTH chars FROM expr)."
  sql_function btrim(expr, chars)
  @doc "Alternate form of TRIM(LEADING chars FROM expr)."
  sql_function ltrim(expr)
  @doc "Alternate form of TRIM(LEADING chars FROM expr)."
  sql_function ltrim(expr, chars)
  @doc "Alternate form of TRIM(TRAILING chars FROM expr)."
  sql_function rtrim(expr)
  @doc "Alternate form of TRIM(TRAILING chars FROM expr)."
  sql_function rtrim(expr, chars)
end
