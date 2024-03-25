defmodule Druid.Client.Native do
  @moduledoc """
  Builds requests for Druid's native API.
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
end
