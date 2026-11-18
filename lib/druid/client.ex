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

  ## Options

  `request/2` and `request!/2` take:

    * `:host`, `:port` - Where Druid is. Required.
    * `:scheme` - `"http"` (the default) or `"https"`.
    * `:auth` - Credentials sent with every request, as the `authorization`
      header. Use `{:basic, "user:password"}` for Druid's basic security
      extension, or `{:bearer, token}`, `:netrc`, `{:netrc, path}`, a raw
      header value, or a 0-arity function returning one of these (see
      `Req.Steps.auth/1`). A `{module, function, args}` tuple is called on
      each request and must return one of these, which keeps rotating
      credentials out of compile-time config. Basic credentials are only
      encoded, not encrypted, so use `scheme: "https"` with them.
    * `:redirect_trusted` - Send `:auth` on redirects to another host.
      Druid's Coordinator and Overlord redirect to their leader, which is
      usually another host, and by default the credentials are dropped
      there. Not needed when going through the Router.
    * `:receive_timeout` - How long to wait for a response, in milliseconds.
      Passed to `Req`, which defaults it to `15_000`.
    * `:plug`, `:adapter`, `:finch` - Passed to `Req`.
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
    {body, _decode_time} = timed_request!(request, opts)
    body
  end

  # Like request!/2, but also returns how long decoding the response body
  # took, in native time units, for the adapter's query telemetry.
  @doc false
  @spec timed_request!(Req.Request.t(), Keyword.t()) :: {term, integer}
  def timed_request!(request, opts) do
    request_opts =
      [base_url: base_url(opts)]
      |> put_present(:plug, Keyword.get(opts, :plug))
      |> put_present(:adapter, Keyword.get(opts, :adapter))
      |> put_present(:finch, Keyword.get(opts, :finch))
      |> put_present(:auth, opts |> Keyword.get(:auth) |> auth())
      |> put_present(:redirect_trusted, Keyword.get(opts, :redirect_trusted))
      |> put_present(:receive_timeout, Keyword.get(opts, :receive_timeout))

    response = Req.request!(request, [decode_body: false] ++ request_opts)
    decode_start = System.monotonic_time()
    body = decode_body(response)
    decode_time = System.monotonic_time() - decode_start

    case response.status do
      code when code in 200..299 ->
        {body, decode_time}

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

  # An MFA can sit in config where a function can't, and is called on every
  # request so a rotating token is read fresh each time.
  defp auth({module, fun, args}) when is_atom(module) and is_atom(fun) and is_list(args),
    do: fn -> apply(module, fun, args) end

  defp auth(auth), do: auth

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
