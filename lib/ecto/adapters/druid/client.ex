defmodule Ecto.Adapters.Druid.Client do
  alias Req.Request

  @api_path "/druid/v2/sql"

  def execute(query, params, opts) do
    client(opts)
    |> Req.post(body: body(query, params, opts))
  end

  defp client(opts) do
    Req.new(url: url(opts))
    |> Request.put_header("Content-Type", "application/json")
  end

  defp url(opts) do
    host = Keyword.fetch!(opts, :host)

    "#{host}#{@api_path}"
  end

  defp body(query, params, opts) do
    Keyword.get(opts, :context, %{})

    %{
      query: query,
      parameters: params,
      context: %{
        sqlQueryId: Ecto.UUID.generate(),
        sqlStringifyArrays: false,
        skipEmptyBuckets: false,
        enableWindowing: true
      },
      resultFormat: "object",
      header: true,
      typesHeader: true
    }
  end
end
