defmodule Druid.Client do
  @moduledoc """
  A client for Druid's HTTP API.

  The modules under `Druid.Client` build `Req` requests for each part of the
  API, and `request/2` or `request!/2` send them:

    * `Druid.Client.SQL` and `Druid.Client.SQL.Statement` - SQL queries,
      SQL-based ingestion, and queries from deep storage.
    * `Druid.Client.Native` - Native JSON queries.
    * `Druid.Client.Task` and `Druid.Client.Supervisor` - Ingestion tasks
      and supervisors.
    * `Druid.Client.DataSource` and `Druid.Client.Metadata` - Data sources,
      segments, and segment loading.
    * `Druid.Client.Compaction`, `Druid.Client.Retention`,
      `Druid.Client.Lookup`, and `Druid.Client.Config` - Cluster
      configuration.
    * `Druid.Client.Status` - Service health and leaders.

  Most requests can go to the Router, which forwards them to the right
  service.
  """

  @default_scheme "http"

  defmodule RequestError do
    @moduledoc """
    Raised when Druid responds with an error status. `:status` is the HTTP
    status and `:body` the decoded response body.
    """
    defexception [:message, :status, :body]
  end

  @doc """
  Makes a request to Druid.

  ## Examples

      Druid.Client.Task.all()
      |> Druid.Client.request(host: "localhost", port: 8082)
  """
  @spec request(Req.Request.t(), Keyword.t()) :: {:ok, term} | {:error, term}
  def request(req, opts) do
    {:ok, request!(req, opts)}
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Makes a request to Druid.

  ## Examples

      Druid.Client.Task.all()
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @spec request!(Req.Request.t(), Keyword.t()) :: term
  def request!(request, opts) do
    request_opts =
      [base_url: base_url(opts)]
      |> put_present(:plug, Keyword.get(opts, :plug))
      |> put_present(:adapter, Keyword.get(opts, :adapter))
      |> put_present(:finch, Keyword.get(opts, :finch))

    response = Req.request!(request, [decode_body: false] ++ request_opts)
    body = decode_body(response)

    case response.status do
      code when code in 200..299 ->
        body

      code when code in 400..599 ->
        raise RequestError,
          message: "Error (#{response.status}) when querying Druid.\n\t#{inspect(body)}",
          status: response.status,
          body: body

      _ ->
        raise RuntimeError,
              "Unexpected error (#{response.status}) when querying Druid.\n\t#{inspect(response)}"
    end
  end

  # Druid sends some plain text answers, such as the leader's address, as
  # application/json, so fall back to the raw body when it is not JSON.
  defp decode_body(%Req.Response{body: body} = response) when is_binary(body) and body != "" do
    json? =
      response
      |> Req.Response.get_header("content-type")
      |> Enum.any?(&String.contains?(&1, "json"))

    with true <- json?, {:ok, decoded} <- Jason.decode(body) do
      decoded
    else
      _ -> body
    end
  end

  defp decode_body(response), do: response.body

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

  defp put_present(opts, key, value) do
    case value do
      nil -> opts
      _ -> Keyword.put(opts, key, value)
    end
  end
end
