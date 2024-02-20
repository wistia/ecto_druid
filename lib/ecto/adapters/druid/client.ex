defmodule Ecto.Adapters.Druid.Client do
  @default_protocol "http"
  @api_path "/druid/v2/sql"

  defmodule RequestError do
    defexception [:message]
  end

  def execute(query, params, opts) do
    response = post!(query, params, opts)

    case response.status do
      code when code in 200..299 ->
        response.body["json"]

      code when code in 400..599 ->
        raise RequestError,
              "Error (#{response.status}) when querying Druid.#{inspect(response.body["json"])}"

      _ ->
        raise RuntimeError,
              "Unexpected error (#{response.status}) when querying Druid.\n\t#{inspect(response)}"
    end
  end

  defp post!(query, params, opts) do
    client(opts) |> Req.post!(json: body(query, params, opts))
  end

  defp client(opts) do
    Req.new(url: url(opts))
  end

  defp url(opts) do
    protocol = Keyword.get(opts, :protocol, @default_protocol)
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)
    path = Keyword.get(opts, :path, @api_path)

    %URI{
      scheme: protocol,
      host: host,
      port: port,
      path: path
    }
    |> URI.to_string()
  end

  defp body(query, params, opts) do
    context = Keyword.get(opts, :context, %{})

    %{
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
  end
end
