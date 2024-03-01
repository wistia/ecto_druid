defmodule Druid.Client.SQL do
  @query_path "/druid/v2/sql"
  @spec query(String.t(), list(), Keyword.t()) :: Req.t()
  def query(query, params, opts) do
    context = Keyword.get(opts, :context, %{})

    body = %{
      query: query,
      parameters: params,
      context:
        Map.merge(
          %{
            sqlQueryId: Ecto.UUID.generate(),
            sqlStringifyArrays: false,
            skipEmptyBuckets: false,
            enableWindowing: true
          },
          context
        ),
      resultFormat: "object",
      header: true,
      typesHeader: true
    }

    Req.new(method: :post, url: @query_path, json: body)
  end

  @insert_path "/druid/v2/sql/task"
  @spec insert(String.t(), list(), Keyword.t()) :: Req.t()
  def insert(query, params, opts) do
    context = Keyword.get(opts, :context, %{})

    body = %{
      query: query,
      parameters: params,
      context:
        Map.merge(
          %{
            sqlQueryId: Ecto.UUID.generate(),
            sqlStringifyArrays: false,
            skipEmptyBuckets: false,
            enableWindowing: true
          },
          context
        )
    }

    Req.new(method: :post, url: @insert_path, json: body)
    |> IO.inspect(label: "Druid.Client.SQL.insert", limit: :infinity)
  end
end
