defmodule Druid.Client.ConfigTest do
  use Druid.ClientCase, async: true
  alias Druid.Client.Config
  alias Plug.Conn

  for {kind, path} <- [
        coordinator: "/druid/coordinator/v1/config",
        broker: "/druid/coordinator/v1/broker/config",
        worker: "/druid/indexer/v1/worker"
      ] do
    describe "#{kind}" do
      test "get/1" do
        assert_request(Config.get(unquote(kind)), "GET", unquote(path))
      end

      test "set/3 records the author and comment" do
        config = %{"key" => "value"}

        conn =
          assert_request(
            Config.set(unquote(kind), config, author: "me", comment: "why"),
            "POST",
            unquote(path),
            "",
            config
          )

        assert Conn.get_req_header(conn, "x-druid-author") == ["me"]
        assert Conn.get_req_header(conn, "x-druid-comment") == ["why"]
      end

      test "history/2" do
        assert_request(
          Config.history(unquote(kind), count: 3),
          "GET",
          unquote(path) <> "/history",
          "count=3"
        )
      end
    end
  end
end
