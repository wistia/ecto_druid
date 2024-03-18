defmodule TestPlug do
  use Plug.Builder
  alias Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)

    with {:ok, body} <- Jason.decode(body) do
      send(self(), {:request, conn, body})
    else
      _ -> send(self(), {:request, conn, nil})
    end

    Conn.send_resp(conn, 204, "No Content")
  end
end
