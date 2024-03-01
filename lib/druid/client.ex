defmodule Druid.Client do
  @default_scheme "http"

  defmodule RequestError do
    defexception [:message]
  end

  @spec request(Req.t(), Keyword.t()) :: {:ok, term} | {:error, term}
  def request(req, opts) do
    {:ok, request!(req, opts)}
  rescue
    error ->
      {:error, error}
  end

  @spec request!(Req.t(), Keyword.t()) :: term
  def request!(request, opts) do
    response = Req.request!(request, base_url: base_url(opts))

    case response.status do
      code when code in 200..299 ->
        response.body

      code when code in 400..599 ->
        raise RequestError,
              "Error (#{response.status}) when querying Druid.\n\t#{inspect(response.body)}"

      _ ->
        raise RuntimeError,
              "Unexpected error (#{response.status}) when querying Druid.\n\t#{inspect(response)}"
    end
  end

  defp base_url(opts) do
    scheme = Keyword.get(opts, :scheme, @default_scheme)
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)

    %URI{
      scheme: scheme,
      host: host,
      port: port
    }
    |> URI.to_string()
  end
end
