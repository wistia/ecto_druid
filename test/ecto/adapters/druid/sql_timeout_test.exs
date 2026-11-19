defmodule Ecto.Adapters.Druid.SQLTimeoutTest do
  use ExUnit.Case
  import Ecto.Query
  alias Ecto.Adapters.Druid.{TestRepo, Wikipedia}

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  # Fails every SQL query with `reason` and answers cancels with `cancels` in
  # turn, then 202s, sending each request's method, path and receive timeout
  # to the test process. A cancel answer is a status or a transport error.
  defp adapter(reason, cancels \\ []) do
    test = self()
    {:ok, cancels} = Agent.start_link(fn -> cancels end)

    fn request ->
      send(test, {request.method, request.url.path, request.options[:receive_timeout]})

      case request.method do
        :post ->
          {request, %Req.TransportError{reason: reason}}

        :delete ->
          case Agent.get_and_update(cancels, fn
                 [answer | rest] -> {answer, rest}
                 [] -> {202, []}
               end) do
            status when is_integer(status) -> {request, Req.Response.new(status: status)}
            error -> {request, %Req.TransportError{reason: error}}
          end
      end
    end
  end

  defp deletes do
    receive do
      {:delete, _path, _timeout} -> 1 + deletes()
    after
      0 -> 0
    end
  end

  defp pages_query, do: from(w in Wikipedia, select: w.page)

  test "Repo.all/2 cancels the query when the request times out" do
    assert_raise Req.TransportError, ~r/timeout/, fn ->
      TestRepo.all(pages_query(),
        adapter: adapter(:timeout),
        receive_timeout: 1,
        context: %{sqlQueryId: "slow"}
      )
    end

    assert_received {:post, "/druid/v2/sql", 1}
    assert_received {:delete, "/druid/v2/sql/slow", cancel_timeout}
    assert cancel_timeout != 1
  end

  test "Repo.all/2 cancels by the generated sqlQueryId" do
    assert_raise Req.TransportError, fn ->
      TestRepo.all(pages_query(), adapter: adapter(:timeout))
    end

    assert_received {:delete, "/druid/v2/sql/" <> query_id, _}
    assert {:ok, _} = Ecto.UUID.cast(query_id)
  end

  test "Repo.stream/2 cancels the query when the request times out" do
    stream =
      TestRepo.stream(pages_query(), adapter: adapter(:timeout), context: %{sqlQueryId: "slow"})

    assert_raise Req.TransportError, fn -> Enum.to_list(stream) end
    assert_received {:delete, "/druid/v2/sql/slow", _}
  end

  test "to_native/2 cancels the query when the request times out" do
    assert_raise Req.TransportError, fn ->
      TestRepo.to_native(pages_query(),
        adapter: adapter(:timeout),
        context: %{sqlQueryId: "slow"}
      )
    end

    assert_received {:delete, "/druid/v2/sql/slow", _}
  end

  # The Broker only knows the query's id once it starts running it
  test "retries a cancel that gets a 404" do
    assert_raise Req.TransportError, fn ->
      TestRepo.all(pages_query(), adapter: adapter(:timeout, [404, 404]))
    end

    assert deletes() == 3
  end

  test "retries a cancel that fails without a response" do
    assert_raise Req.TransportError, fn ->
      TestRepo.all(pages_query(), adapter: adapter(:timeout, [:closed, 503]))
    end

    assert deletes() == 3
  end

  test "stops retrying a cancel that keeps getting 404s" do
    assert_raise Req.TransportError, fn ->
      TestRepo.all(pages_query(), adapter: adapter(:timeout, List.duplicate(404, 10)))
    end

    assert deletes() == 6
  end

  test "doesn't retry a cancel that fails for another reason" do
    assert_raise Req.TransportError, fn ->
      TestRepo.all(pages_query(), adapter: adapter(:timeout, [500]))
    end

    assert deletes() == 1
  end

  test "doesn't cancel when the request fails for another reason" do
    assert_raise Req.TransportError, ~r/econnrefused|connection refused/, fn ->
      TestRepo.all(pages_query(), adapter: adapter(:econnrefused))
    end

    assert_received {:post, "/druid/v2/sql", _}
    refute_received {:delete, _, _}
  end
end
