defmodule Druid.Client.Native do
  @moduledoc """
  Builds requests for Druid's [JSON querying API](https://druid.apache.org/docs/latest/api-reference/json-querying-api).
  """

  @doc """
  Builds a query request for Druid's native query API.

  ## Examples

      Druid.Client.Native.query(%{
        queryType: "timeseries",
        dataSource: "wikipedia",
        intervals: ["2015-09-12T00:00:00.000Z/2015-09-13T00:00:00.000Z"],
        granularity: "all",
        aggregations: [
          %{type: "count", name: "count"}
        ]
      })
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @query_path "/druid/v2/"
  @spec query(map()) :: Req.Request.t()
  def query(query) do
    Req.new(method: :post, url: @query_path, json: query)
  end

  @doc """
  Builds a request to list the segments a native query would read and the
  servers that hold them, without running it.
  """
  @spec candidates(map()) :: Req.Request.t()
  def candidates(query) do
    Req.new(method: :post, url: @query_path <> "candidates", json: query)
  end

  @doc """
  Builds a request to cancel a running native query by the `queryId` in its
  context.

  ## Examples

      Druid.Client.Native.cancel("my-query")
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @spec cancel(String.t()) :: Req.Request.t()
  def cancel(query_id) do
    Req.new(method: :delete, url: Druid.Client.Util.path("/druid/v2", [query_id]))
  end
end
