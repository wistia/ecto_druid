defmodule Ecto.Adapters.Druid.BrokerStreamTest do
  use ExUnit.Case
  import Ecto.Query
  alias Ecto.Adapters.Druid.{TestRepo, Wikipedia}

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  defp pages_query, do: from(w in Wikipedia, select: w.page)

  # A Broker that answers the query with `chunks`, one at a time, through
  # Req's `into` callback as a real streamed response would arrive. It sends
  # {:sent, chunk} to the test before each one, and the query body on
  # {:query, body}. A chunk can be `{:error, reason}`, to fail the response
  # there. Cancels get a 202 and are sent as {:cancel, path}.
  defp broker(chunks, status \\ 200) do
    test = self()

    fn request ->
      case request.method do
        :post ->
          send(test, {:query, request.body |> IO.iodata_to_binary() |> Jason.decode!()})

          response =
            Req.Response.new(status: status, headers: %{"content-type" => ["application/json"]})

          Enum.reduce_while(chunks, {request, response}, fn
            {:error, reason}, {request, _response} ->
              {:halt, {request, %Req.TransportError{reason: reason}}}

            chunk, acc ->
              send(test, {:sent, chunk})
              {:cont, acc} = request.into.({:data, chunk}, acc)
              {:cont, acc}
          end)

        :delete ->
          send(test, {:cancel, request.url.path})
          {request, Req.Response.new(status: 202)}
      end
    end
  end

  test "asks for arrayLines and decodes rows split across chunks" do
    chunks = [~s(["a"]\n["b), ~s("]\n["c"]), "\n", "\n"]
    stream = TestRepo.stream(pages_query(), adapter: broker(chunks))

    assert Enum.to_list(stream) == ["a", "b", "c"]
    assert_received {:query, %{"resultFormat" => "arrayLines", "header" => false}}
    refute_received {:cancel, _}
  end

  test "reads an empty result" do
    assert TestRepo.stream(pages_query(), adapter: broker(["\n\n"])) |> Enum.to_list() == []
  end

  test "reads the body only as fast as the rows are taken" do
    chunks = for(page <- ~w(a b c d e f), do: ~s(["#{page}"]\n)) ++ ["\n"]
    stream = TestRepo.stream(pages_query(), adapter: broker(chunks))

    assert Enum.take(stream, 1) == ["a"]

    # The chunk after the one taken may have been read ahead, but no more
    assert_received {:sent, ~s(["a"]\n)}
    refute_received {:sent, ~s(["c"]\n)}

    # Halting early cancels the query, which may still be running
    assert_received {:cancel, "/druid/v2/sql/" <> _}
  end

  test "raises when the response ends without its trailer" do
    chunks = [~s(["a"]\n["b"]\n)]
    stream = TestRepo.stream(pages_query(), adapter: broker(chunks), context: %{sqlQueryId: "q1"})

    assert_raise RuntimeError, ~r/query q1 ended before its last row/, fn ->
      Enum.to_list(stream)
    end

    assert_received {:cancel, "/druid/v2/sql/q1"}
  end

  test "raises and cancels when the response fails partway" do
    chunks = [~s(["a"]\n), {:error, :timeout}]
    stream = TestRepo.stream(pages_query(), adapter: broker(chunks), context: %{sqlQueryId: "q1"})

    assert_raise Req.TransportError, ~r/timeout/, fn -> Enum.to_list(stream) end
    assert_received {:cancel, "/druid/v2/sql/q1"}
  end

  test "raises Druid's error for an error response" do
    error = ~s({"error":"druidException","errorCode":"invalidInput","errorMessage":"bad"})
    stream = TestRepo.stream(pages_query(), adapter: broker([error], 400))

    assert %Druid.Client.RequestError{status: 400, error_code: "invalidInput"} =
             catch_error(Enum.to_list(stream))

    refute_received {:cancel, _}
  end

  test "works with a plug" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s(["a"]\n["b"]\n\n))
    end

    assert TestRepo.stream(pages_query(), plug: plug) |> Enum.to_list() == ["a", "b"]
  end

  test "leaves no messages or processes behind" do
    chunks = for(page <- ~w(a b c), do: ~s(["#{page}"]\n)) ++ ["\n"]
    {:links, links} = Process.info(self(), :links)

    assert TestRepo.stream(pages_query(), adapter: broker(chunks)) |> Enum.take(1) == ["a"]

    assert Process.info(self(), :links) == {:links, links}

    {:messages, messages} = Process.info(self(), :messages)
    assert Enum.all?(messages, &match?({tag, _} when tag in [:sent, :query, :cancel], &1))
  end
end
