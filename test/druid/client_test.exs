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
