defmodule Druid.Client.SQL.Statement do
  @moduledoc """
  Builds requests for Druid's [query from deep storage API](https://druid.apache.org/docs/latest/api-reference/sql-api#query-from-deep-storage).

  Statements run asynchronously as SQL-based ingestion tasks, so they can read
  segments that are only in deep storage and return more rows than a Broker
  would. Submit a statement, poll `status/2` until its `"state"` is
  `"SUCCESS"`, then page through `results/2`.

  ## Examples

      %{"queryId" => id} =
        Druid.Client.SQL.Statement.submit("SELECT * FROM wikipedia")
        |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.SQL.Statement.status(id)
      |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.SQL.Statement.results(id, page: 0)
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """

  import Druid.Client.Util, only: [params: 2, path: 2]

  @statements_path "/druid/v2/sql/statements"

  @doc """
  Builds a request to submit a statement. Druid responds with the statement's
  `"queryId"` and `"state"`.

  ## Options

    * `:context` - A map of [SQL-based ingestion context parameters](https://druid.apache.org/docs/latest/multi-stage-query/reference#context-parameters),
      merged over the defaults. `executionMode` is always `"ASYNC"`. Set
      `selectDestination: "durableStorage"` to keep large results in durable
      storage.
  """
  @spec submit(String.t(), list(), Keyword.t()) :: Req.Request.t()
  def submit(query, params \\ [], opts \\ []) do
    context =
      opts
      |> Keyword.get(:context, %{})
      |> Druid.Client.SQL.context()
      |> Map.put(:executionMode, "ASYNC")

    Req.new(
      method: :post,
      url: @statements_path,
      json: %{query: query, parameters: params, context: context}
    )
  end

  @doc """
  Builds a request to get a statement's state, schema, and result page
  details.

  ## Options

    * `:detail` - When `true`, also return the query's stage and counter
      details.
  """
  @spec status(String.t(), Keyword.t()) :: Req.Request.t()
  def status(query_id, opts \\ []) do
    Req.new(
      method: :get,
      url: path(@statements_path, [query_id]),
      params: params(opts, detail: "detail")
    )
  end

  @doc """
  Builds a request to get a finished statement's results.

  ## Options

    * `:page` - Return only this page of results, numbered from 0. All pages
      are returned when omitted.
    * `:result_format` - `"object"` (the default), `"array"`, `"objectLines"`,
      `"arrayLines"`, or `"csv"`.
    * `:filename` - Have Druid send the results as a download with this name.
  """
  @spec results(String.t(), Keyword.t()) :: Req.Request.t()
  def results(query_id, opts \\ []) do
    Req.new(
      method: :get,
      url: path(@statements_path, [query_id, "results"]),
      params: params(opts, page: "page", result_format: "resultFormat", filename: "filename")
    )
  end

  @doc """
  Builds a request to cancel a running statement.
  """
  @spec cancel(String.t()) :: Req.Request.t()
  def cancel(query_id) do
    Req.new(method: :delete, url: path(@statements_path, [query_id]))
  end
end
