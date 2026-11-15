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
end
