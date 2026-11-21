defmodule Druid.ClientTest do
  use ExUnit.Case, async: true
  alias Druid.Client

  defp respond(status, content_type, body) do
    fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type(content_type)
      |> Plug.Conn.send_resp(status, body)
    end
  end

  defp request(plug),
    do: Client.request(Req.new(url: "/"), plug: plug, host: "localhost", port: 1)

  test "decodes JSON bodies" do
    assert request(respond(200, "application/json", ~s({"a":1}))) == {:ok, %{"a" => 1}}
  end

  test "returns plain text that Druid labels as JSON" do
    assert request(respond(200, "application/json", "http://localhost:8081")) ==
             {:ok, "http://localhost:8081"}
  end

  test "returns errors with the decoded body" do
    assert {:error, %Client.RequestError{status: 404, body: %{"error" => "nope"}}} =
             request(respond(404, "application/json", ~s({"error":"nope"})))
  end

  describe "RequestError" do
    defp error(status, content_type, body) do
      plug = respond(status, content_type, body)
      opts = [plug: plug, host: "localhost", port: 1, retry: false]
      {:error, error} = Client.request(Req.new(url: "/"), opts)
      error
    end

    test "copies Druid's error fields out of the body" do
      body =
        ~s({"error":"druidException","errorCode":"invalidInput","persona":"USER",) <>
          ~s("category":"INVALID_INPUT","errorMessage":"Object 'nope' not found","context":{}})

      assert %Client.RequestError{
               status: 400,
               error_code: "invalidInput",
               category: "INVALID_INPUT",
               error_message: "Object 'nope' not found",
               body: %{"persona" => "USER"}
             } = error = error(400, "application/json", body)

      assert Exception.message(error) ==
               "Druid responded with 400 (invalidInput): Object 'nope' not found"
    end

    test "reads the code from older error bodies" do
      body = ~s({"error":"Query timeout","errorMessage":"Query timed out","errorClass":"x"})

      assert %Client.RequestError{error_code: "Query timeout", category: nil} =
               error = error(504, "application/json", body)

      assert Exception.message(error) ==
               "Druid responded with 504 (Query timeout): Query timed out"
    end

    test "uses a lone error as the message" do
      assert %Client.RequestError{error_code: nil, error_message: "bad task"} =
               error = error(400, "application/json", ~s({"error":"bad task"}))

      assert Exception.message(error) == "Druid responded with 400: bad task"
    end

    test "falls back to the body when it isn't a Druid error" do
      assert %Client.RequestError{error_code: nil, category: nil, error_message: nil} =
               error = error(502, "text/html", "Bad Gateway")

      assert Exception.message(error) == ~s(Druid responded with 502: "Bad Gateway")
    end
  end

  describe "retries" do
    # Answers 503 and counts the attempts
    defp unavailable do
      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      plug = fn conn ->
        Agent.update(attempts, &(&1 + 1))
        Plug.Conn.send_resp(conn, 503, "")
      end

      {plug, fn -> Agent.get(attempts, & &1) end}
    end

    defp retried(opts) do
      {plug, attempts} = unavailable()
      opts = Keyword.merge([plug: plug, host: "localhost", port: 1, retry_log_level: false], opts)
      assert {:error, %Client.RequestError{status: 503}} = Client.request(Req.new(url: "/"), opts)
      attempts.()
    end

    test "passes the retry options to Req" do
      assert retried(retry_delay: 0) == 4
      assert retried(retry_delay: 0, max_retries: 1) == 2
      assert retried(retry: false) == 1
    end
  end

  describe ":auth" do
    # Answers 200 and reports the authorization header and host of each request
    defp echo_auth(test_pid) do
      fn conn ->
        send(test_pid, {:auth, conn.host, Plug.Conn.get_req_header(conn, "authorization")})
        Req.Test.json(conn, %{})
      end
    end

    defp auth_request(opts) do
      opts = Keyword.merge([plug: echo_auth(self()), host: "localhost", port: 1], opts)
      Client.request(Req.new(url: "/"), opts)
    end

    def token(agent), do: {:bearer, Agent.get_and_update(agent, &{"t#{&1}", &1 + 1})}

    test "sends basic credentials" do
      assert {:ok, _} = auth_request(auth: {:basic, "user:pass"})
      assert_received {:auth, _, ["Basic " <> encoded]}
      assert Base.decode64!(encoded) == "user:pass"
    end

    test "sends no header without :auth" do
      assert {:ok, _} = auth_request([])
      assert_received {:auth, _, []}
    end

    test "calls an MFA on every request" do
      {:ok, agent} = Agent.start_link(fn -> 1 end)
      auth = {__MODULE__, :token, [agent]}

      assert {:ok, _} = auth_request(auth: auth)
      assert {:ok, _} = auth_request(auth: auth)
      assert_received {:auth, _, ["Bearer t1"]}
      assert_received {:auth, _, ["Bearer t2"]}
    end

    test "keeps credentials on a redirect to another host only when trusted" do
      test_pid = self()

      plug = fn
        %{host: "localhost"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "http://leader:2/")
          |> Plug.Conn.send_resp(307, "")

        conn ->
          echo_auth(test_pid).(conn)
      end

      assert {:ok, _} = auth_request(plug: plug, auth: {:bearer, "t"})
      assert_received {:auth, "leader", []}

      assert {:ok, _} = auth_request(plug: plug, auth: {:bearer, "t"}, redirect_trusted: true)
      assert_received {:auth, "leader", ["Bearer t"]}
    end
  end
end
