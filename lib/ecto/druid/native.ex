defmodule Ecto.Druid.Native do
  @moduledoc """
  Helpers for Druid's [native JSON queries](https://druid.apache.org/docs/latest/querying/).

  Each native query type nests its results differently. `rows/3` flattens
  them into one map per row, keyed by column name:

      query = %{
        queryType: "topN",
        dataSource: "wikipedia",
        intervals: ["2016-06-27/2016-06-28"],
        granularity: "all",
        dimension: "channel",
        metric: "edits",
        threshold: 2,
        aggregations: [%{type: "count", name: "edits"}]
      }

      MyApp.DruidRepo.native_query(query, raw: true)
      |> Ecto.Druid.Native.rows(query)
      #=> [%{"__time" => "2016-06-27T00:00:00.000Z", "channel" => "#en.wikipedia", "edits" => 6650},
      #    %{"__time" => "2016-06-27T00:00:00.000Z", "channel" => "#sh.wikipedia", "edits" => 3969}]

  `native_query/2` on the repo already does this for the query types `rows/3`
  supports, unless it's passed `raw: true`. See the
  [Native Queries guide](native_queries.md).
  """

  @supported ~w(timeseries topN groupBy scan windowOperator)

  @doc """
  Flattens the results of a native query into a list of maps, one per row,
  keyed by column name. Pass the query that produced the results, as either
  atom or string keys.

  | Query type | Columns |
  | --- | --- |
  | `timeseries` | `"__time"`, then the aggregations and post-aggregations |
  | `topN` | `"__time"`, the dimension, then the aggregations and post-aggregations |
  | `groupBy` | `"__time"` (unless the granularity is `all`), the dimensions, then the aggregations and post-aggregations |
  | `scan` | the scanned columns |

  `"__time"` holds the bucket's timestamp as Druid sends it: an ISO 8601
  string for `timeseries`, `topN` and `groupBy`, and epoch milliseconds for
  `scan`. Values are otherwise returned as Druid sends them.

  `groupBy` results with the `resultAsArray` context flag and `scan` results
  in the `compactedList` format are paired with their column names.
  `windowOperator` results are bare arrays, so they need their names passed
  as `:columns`.

  ## Options

    * `:columns` - Column names for results that are arrays, in order. Overrides
      the names worked out from the query.

  ## Examples

      iex> query = %{queryType: "timeseries", granularity: "day", aggregations: [%{type: "count", name: "rows"}]}
      iex> results = [%{"timestamp" => "2016-06-27T00:00:00.000Z", "result" => %{"rows" => 24433}}]
      iex> Ecto.Druid.Native.rows(results, query)
      [%{"__time" => "2016-06-27T00:00:00.000Z", "rows" => 24433}]

      iex> query = %{queryType: "groupBy", granularity: "all", dimensions: ["channel"],
      ...>   aggregations: [%{type: "count", name: "rows"}], context: %{resultAsArray: true}}
      iex> Ecto.Druid.Native.rows([["#en.wikipedia", 11549]], query)
      [%{"channel" => "#en.wikipedia", "rows" => 11549}]
  """
  @spec rows([term()], map(), Keyword.t()) :: [%{String.t() => term()}]
  def rows(results, query, opts \\ []) when is_list(results) and is_map(query) do
    query = stringify_keys(query)
    columns = Keyword.get_lazy(opts, :columns, fn -> columns(query) end)

    case query["queryType"] do
      "timeseries" ->
        Enum.map(results, fn %{"timestamp" => time, "result" => result} ->
          Map.put(result, "__time", time)
        end)

      "topN" ->
        Enum.flat_map(results, fn %{"timestamp" => time, "result" => result} ->
          Enum.map(result, &Map.put(&1, "__time", time))
        end)

      "groupBy" ->
        Enum.map(results, fn
          %{"event" => event} = row ->
            if all_granularity?(query),
              do: event,
              else: Map.put(event, "__time", row["timestamp"])

          row when is_list(row) ->
            zip!(columns, row, query)
        end)

      "scan" ->
        Enum.flat_map(results, fn %{"events" => events} = batch ->
          Enum.map(events, fn
            event when is_map(event) -> event
            event when is_list(event) -> zip!(batch["columns"] || columns, event, query)
          end)
        end)

      "windowOperator" ->
        Enum.map(results, &zip!(columns, &1, query))

      other ->
        raise ArgumentError,
              "rows/3 supports the #{Enum.join(@supported, ", ")} query types, got: #{inspect(other)}"
    end
  end

  @doc """
  Builds an expression [virtual column](https://druid.apache.org/docs/latest/querying/virtual-columns),
  which the rest of the query can read like any other column.

      iex> import Ecto.Druid.Native.Expression
      iex> Ecto.Druid.Native.virtual_column("net", expr(added - deleted), "LONG")
      %{type: "expression", name: "net", expression: expr(added - deleted), outputType: "LONG"}
  """
  @spec virtual_column(
          String.t() | atom(),
          Ecto.Druid.Native.Expression.t() | String.t(),
          String.t() | nil
        ) :: map()
  def virtual_column(name, expression, output_type \\ nil) do
    Ecto.Druid.Native.Filter.put_present(
      %{type: "expression", name: name, expression: expression},
      :outputType,
      output_type
    )
  end

  @doc """
  Builds a [dimension spec](https://druid.apache.org/docs/latest/querying/dimensionspecs),
  for when a dimension needs a different output name or type than the column.
  A bare column name works as a dimension otherwise.

  ## Options

    * `:name` - The output name. Defaults to the column.
    * `:type` - The output type, such as `"LONG"`. Defaults to `"STRING"`.

  ## Examples

      iex> Ecto.Druid.Native.dimension("namespace", name: "ns")
      %{type: "default", dimension: "namespace", outputName: "ns"}
  """
  @spec dimension(String.t() | atom(), Keyword.t()) :: map()
  def dimension(column, opts \\ []) do
    Ecto.Druid.Native.Filter.put_present(
      %{type: "default", dimension: column, outputName: Keyword.get(opts, :name, column)},
      :outputType,
      opts[:type]
    )
  end

  @doc false
  # Whether rows/3 flattens the results of this query's type.
  @spec flattens?(map()) :: boolean()
  def flattens?(query), do: stringify_keys(query)["queryType"] in @supported

  @doc false
  # The columns each row of a native query has, in the order Druid returns
  # them as arrays, or nil when the query alone doesn't say.
  @spec columns(map()) :: [String.t()] | nil
  def columns(query) do
    query = stringify_keys(query)
    outputs = aggregators(query)

    case query["queryType"] do
      "timeseries" ->
        ["__time" | List.wrap(query["context"]["timestampResultField"])] ++ outputs

      "topN" ->
        ["__time", dimension_name(query["dimension"]) | outputs]

      "groupBy" ->
        time = if all_granularity?(query), do: [], else: ["__time"]
        time ++ Enum.map(query["dimensions"] || [], &dimension_name/1) ++ outputs

      "scan" ->
        case query["columns"] do
          [_ | _] = columns -> columns
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp aggregators(query) do
    Enum.map((query["aggregations"] || []) ++ (query["postAggregations"] || []), & &1["name"])
  end

  defp dimension_name(dimension) when is_binary(dimension), do: dimension
  defp dimension_name(%{"outputName" => name}) when is_binary(name), do: name
  defp dimension_name(%{"dimension" => name}), do: name

  defp all_granularity?(query) do
    case query["granularity"] do
      nil -> true
      "all" -> true
      %{"type" => "all"} -> true
      _ -> false
    end
  end

  defp zip!(nil, _row, query) do
    raise ArgumentError,
          "#{query["queryType"]} results are arrays, and their column names can't be " <>
            "worked out from the query. Pass them as the :columns option, or pass " <>
            "raw: true to native_query/2 to skip flattening"
  end

  defp zip!(columns, row, _query) when length(columns) == length(row) do
    columns |> Enum.zip(row) |> Map.new()
  end

  defp zip!(columns, row, _query) do
    raise ArgumentError,
          "expected #{length(columns)} values for the columns #{inspect(columns)}, got: #{inspect(row)}"
  end

  # Native queries are written with atom or string keys, and come back from
  # Druid with string keys, so look everything up by string.
  @doc false
  def stringify_keys(query), do: query |> Jason.encode!() |> Jason.decode!()
end
