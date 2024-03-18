defmodule Druid.Client.Native do
  @query_path "/druid/v2/"
  @spec query(map()) :: Req.Request.t()
  def query(query) do
    Req.new(method: :post, url: @query_path, json: query)
  end
end
