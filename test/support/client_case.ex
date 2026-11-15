defmodule Druid.ClientCase do
  @moduledoc """
  Sends client requests to `TestPlug` and asserts on what Druid would receive.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Druid.ClientCase
    end
  end

  @doc """
  Sends `req` to `TestPlug` and returns the received conn and decoded body.
  """
  def request!(req) do
    Druid.Client.request!(req, plug: TestPlug, host: "localhost", port: 8888)
    assert_received {:request, conn, body}
    {conn, body}
  end

  @doc """
  Asserts that `req` sends `method` to `path`, with `query` as its query
  string and `body` as its decoded JSON body.
  """
  def assert_request(req, method, path, query \\ "", body \\ nil) do
    {conn, received} = request!(req)
    assert {conn.method, conn.request_path, conn.query_string} == {method, path, query}
    assert received == body
    conn
  end
end
