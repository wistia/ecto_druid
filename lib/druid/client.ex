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
    * `:retry`, `:max_retries`, `:retry_delay`, `:retry_log_level` - How
      `Req` retries a failed request (see `Req.Steps.retry/1`). By default
      it retries a GET or HEAD that gets a 408, 429, 500, 502, 503 or 504,
      or fails without a response, three times over about seven seconds.
      Some requests set their own default: the `Druid.Client.Status` checks
      don't retry, and `Druid.Client.Task.statuses/1` retries even though
      it is a POST. `retry: false` turns retries off.
    * `:finch` - The name of a running Finch pool to send the request
      through, or a keyword list of Req's `finch:` options.
    * `:plug`, `:adapter` - Passed to `Req`.
    * `:telemetry_metadata` - A map merged into the metadata of this
      request's telemetry events.

  ## Telemetry

  Each request runs in a `[:druid, :request]` span, which emits
  `[:druid, :request, :start]`, then `[:druid, :request, :stop]` when Druid
  responds, whatever the status, or `[:druid, :request, :exception]` when
  no response comes back, for example on a timeout.

  The metadata has the request's `:method`, `:scheme`, `:host`, `:port`
  and `:path`, and anything in `:telemetry_metadata`. Requests sent for a
  repo add its `:repo`. `:stop` adds the response `:status`, and
  `:exception` adds `:kind`, `:reason` and `:stacktrace`. Credentials and
  request bodies are never in the metadata.

  `:stop` and `:exception` measure the `:duration`, and `:stop` the
  `:decode_time` spent decoding the response body, in `:native` time units.
  See the [Telemetry guide](telemetry.md).
  """

  @default_scheme "http"

  defmodule RequestError do
    @moduledoc """
    Raised when Druid responds with an error status. `:status` is the HTTP
    status and `:body` the decoded response body.

    Druid describes most errors with a JSON body, such as
    `%{"error" => "druidException", "errorCode" => "invalidInput",
    "category" => "INVALID_INPUT", "errorMessage" => "..."}`. Its fields
    are copied out so they can be matched on:

      * `:error_code` - Druid's `errorCode`, such as `"invalidInput"` or
        `"notFound"`. Older error bodies, which some native query errors
        still use, carry the code in `error`, such as `"Query timeout"`.
      * `:category` - Druid's `category`, such as `"INVALID_INPUT"`,
        `"NOT_FOUND"`, `"CAPACITY_EXCEEDED"` or `"TIMEOUT"`.
      * `:error_message` - Druid's `errorMessage`, or `error` when that is
        all the body has.

    Each is `nil` when the body doesn't have it.

        case Druid.Client.request(request, opts) do
          {:error, %Druid.Client.RequestError{error_code: "notFound"}} -> ...
        end
    """
    defexception [:message, :status, :body, :error_code, :category, :error_message]

    @type t :: %__MODULE__{
            message: String.t(),
            status: 400..599,
            body: term,
            error_code: String.t() | nil,
            category: String.t() | nil,
            error_message: String.t() | nil
          }

    @impl true
    def exception(opts) do
      status = Keyword.fetch!(opts, :status)
      body = Keyword.get(opts, :body)
      {error_code, category, error_message} = fields(body)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          message(status, error_code, error_message, body)
        end)

      %__MODULE__{
        message: message,
        status: status,
        body: body,
        error_code: error_code,
        category: category,
        error_message: error_message
      }
    end

    # Newer Druid errors are DruidExceptions, with "error" set to
    # "druidException" and the code in "errorCode". Older ones put the code
    # in "error" next to an "errorMessage".
    defp fields(%{} = body) do
      error = string(body["error"])
      error_message = string(body["errorMessage"])

      error_code =
        string(body["errorCode"]) ||
          if(error_message && error != "druidException", do: error)

      {error_code, string(body["category"]), error_message || error}
    end

    defp fields(_body), do: {nil, nil, nil}

    defp string(value) when is_binary(value) and value != "", do: value
    defp string(_value), do: nil

    defp message(status, error_code, error_message, body) do
      prefix = "Druid responded with #{status}"

      case {error_code, error_message} do
        {nil, nil} -> "#{prefix}: #{inspect(body)}"
        {nil, message} -> "#{prefix}: #{message}"
        {code, nil} -> "#{prefix} (#{code})"
        {code, message} -> "#{prefix} (#{code}): #{message}"
      end
    end
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
    send_request!(request, opts, fn response ->
      decode_start = System.monotonic_time()
      body = decode_body(response)
      decode_time = System.monotonic_time() - decode_start
      {{body, decode_time}, body, %{decode_time: decode_time}}
    end)
  end

  # Sends the request in a [:druid, :request] span. `read_body` takes the
  # response and returns {result, body, measurements}: `result` is returned
  # for a 2xx response, and the decoded `body` goes in the error otherwise.
  defp send_request!(request, opts, read_body) do
    base_url = base_url(opts)

    request_opts =
      [base_url: URI.to_string(base_url)]
      |> put_present(:plug, Keyword.get(opts, :plug))
      |> put_present(:adapter, Keyword.get(opts, :adapter))
      |> put_present(:finch, opts |> Keyword.get(:finch) |> finch())
      |> put_present(:auth, opts |> Keyword.get(:auth) |> auth())
      |> put_present(:redirect_trusted, Keyword.get(opts, :redirect_trusted))
      |> put_present(:receive_timeout, Keyword.get(opts, :receive_timeout))
      |> put_retry_opts(opts)

    metadata =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> Map.merge(%{
        method: request.method,
        scheme: base_url.scheme,
        host: base_url.host,
        port: base_url.port,
        path: request_path(request)
      })

    # The status is checked after the span, so an error response is a
    # :stop with its status, and :exception means no response came back
    {response, result, body} =
      :telemetry.span([:druid, :request], metadata, fn ->
        response = Req.request!(request, [decode_body: false] ++ request_opts)
        {result, body, measurements} = read_body.(response)
        {{response, result, body}, measurements, Map.put(metadata, :status, response.status)}
      end)

    case response.status do
      code when code in 200..299 ->
        result

      code when code in 400..599 ->
        raise RequestError, status: response.status, body: body

      _ ->
        raise RuntimeError,
              "Unexpected error (#{response.status}) when querying Druid.\n\t#{inspect(response)}"
    end
  end

  # Streams a response body without holding all of it in memory. The request
  # is sent from a linked process, which hands each chunk of the body to the
  # caller, then reads the next one once the caller has taken it. So the
  # body arrives at the pace the caller uses it, one chunk ahead.
  #
  # stream_open!/2 returns once the first chunk arrives, raising like
  # request!/2 when Druid responds with an error status or doesn't respond
  # in time. stream_next!/1 returns {:data, chunk, stream} or :done, and
  # raises if the response fails partway. stream_close/1 stops the request
  # if it is still running. The [:druid, :request] span covers the whole
  # body, and `:decode_time` is 0, since the caller decodes it.
  @doc false
  @spec stream_open!(Req.Request.t(), Keyword.t()) :: map()
  def stream_open!(request, opts) do
    owner = self()
    ref = make_ref()
    callers = [owner | Process.get(:"$callers", [])]
    logger_metadata = Logger.metadata()

    pid =
      spawn_link(fn ->
        Process.put(:"$callers", callers)
        Logger.metadata(logger_metadata)
        send(owner, {ref, stream_body(request, opts, owner, ref)})
      end)

    stream = %{pid: pid, ref: ref, chunk: nil, done: false}

    case receive_chunk(stream) do
      {:data, chunk, stream} -> %{stream | chunk: chunk}
      :done -> %{stream | done: true}
    end
  end

  @doc false
  @spec stream_next!(map()) :: {:data, binary, map()} | :done
  def stream_next!(%{chunk: chunk} = stream) when is_binary(chunk),
    do: {:data, chunk, %{stream | chunk: nil}}

  def stream_next!(%{done: true}), do: :done
  def stream_next!(stream), do: receive_chunk(stream)

  @doc false
  @spec stream_close(map()) :: :ok
  def stream_close(%{pid: pid, ref: ref}) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    flush(ref)
  end

  defp flush(ref) do
    receive do
      {^ref, _message} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp receive_chunk(%{pid: pid, ref: ref} = stream) do
    receive do
      {^ref, {:data, chunk}} ->
        send(pid, {ref, :cont})
        {:data, chunk, stream}

      {^ref, :done} ->
        :done

      {^ref, {:error, kind, reason, stacktrace}} ->
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  # Runs in the linked process. Each 2xx chunk is sent to the owner, which
  # answers :cont when it has taken it. An error response is collected, to
  # be decoded into the RequestError.
  defp stream_body(request, opts, owner, ref) do
    into = fn {:data, data}, {req, resp} ->
      if resp.status in 200..299 do
        forward(owner, ref, data)
        {:cont, {req, resp}}
      else
        {:cont, {req, %{resp | body: resp.body <> data}}}
      end
    end

    read_body = fn
      %{status: status} = response when status in 200..299 ->
        {response.body, nil, %{decode_time: 0}}

      response ->
        {nil, decode_body(response), %{decode_time: 0}}
    end

    # Adapters that don't stream, such as a test's, return the body whole
    case send_request!(Req.merge(request, into: into), opts, read_body) do
      body when is_binary(body) and body != "" -> forward(owner, ref, body)
      _ -> :ok
    end

    :done
  catch
    kind, reason -> {:error, kind, reason, __STACKTRACE__}
  end

  defp forward(owner, ref, data) do
    send(owner, {ref, {:data, data}})

    receive do
      {^ref, :cont} -> :ok
    end
  end

  defp request_path(%Req.Request{url: %URI{path: path}}) when is_binary(path), do: path
  defp request_path(_request), do: nil

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
  end

  @retry_keys [:retry, :max_retries, :retry_delay, :retry_log_level]

  defp put_retry_opts(request_opts, opts) do
    Enum.reduce(@retry_keys, request_opts, fn key, acc ->
      put_present(acc, key, Keyword.get(opts, key))
    end)
  end

  # Req 0.7 takes the pool name inside its finch: options
  defp finch(name) when is_atom(name) and not is_nil(name), do: [name: name]
  defp finch(finch), do: finch

  defp put_present(opts, key, value) do
    case value do
      nil -> opts
      _ -> Keyword.put(opts, key, value)
    end
  end
end
