defmodule Ecto.Adapters.Druid.FinchTest do
  use ExUnit.Case
  import Ecto.Query
  alias Ecto.Adapters.Druid.TestRepo

  defmodule OtherRepo do
    use Ecto.Repo, otp_app: :ecto_druid, adapter: Ecto.Adapters.Druid
  end

  # Nothing listens here, so requests fail fast, after Finch has picked a pool
  @closed [host: "localhost", port: 1]

  setup context do
    # native_query/2 and to_native/2 read the config from the app env
    Application.put_env(:ecto_druid, OtherRepo, @closed)
    on_exit(fn -> Application.delete_env(:ecto_druid, OtherRepo) end)

    handler = "finch-test-#{inspect(context.test)}"
    :telemetry.attach(handler, [:finch, :request, :start], &__MODULE__.handle_event/4, self())

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  def handle_event(_event, _measurements, %{name: name}, test), do: send(test, {:finch, name})

  test "each repo sends queries through its own pool" do
    start_supervised!({TestRepo, @closed})
    start_supervised!({OtherRepo, @closed})

    assert_raise Req.TransportError, fn ->
      TestRepo.all(from(r in "wikipedia", select: r.page))
    end

    assert_receive {:finch, TestRepo.Finch}

    assert_raise Req.TransportError, fn ->
      OtherRepo.all(from(r in "wikipedia", select: r.page))
    end

    assert_receive {:finch, OtherRepo.Finch}

    assert {:error, _} = OtherRepo.native_query(%{queryType: "timeBoundary", dataSource: "x"})
    assert_receive {:finch, OtherRepo.Finch}

    assert_raise Req.TransportError, fn ->
      OtherRepo.to_native(from(r in "wikipedia", select: r.page))
    end

    assert_receive {:finch, OtherRepo.Finch}
  end

  test "names the pool after the :finch option" do
    start_supervised!({OtherRepo, Keyword.put(@closed, :finch, __MODULE__.CustomFinch)})

    assert Process.whereis(__MODULE__.CustomFinch)

    assert_raise Req.TransportError, fn ->
      OtherRepo.all(from(r in "wikipedia", select: r.page))
    end

    assert_receive {:finch, __MODULE__.CustomFinch}
  end

  test "Druid.Client takes Req's finch: options as well as a pool name" do
    start_supervised!({Finch, name: __MODULE__.ListFinch})
    request = Druid.Client.Status.health()
    opts = @closed ++ [retry: false]

    for finch <- [__MODULE__.ListFinch, [name: __MODULE__.ListFinch]] do
      assert {:error, %Req.TransportError{}} =
               Druid.Client.request(request, Keyword.put(opts, :finch, finch))

      assert_receive {:finch, __MODULE__.ListFinch}
    end
  end

  describe "Druid.SpecTemplates.request_opts/2" do
    alias Druid.SpecTemplates

    test "uses the repo's pool while the repo is running" do
      start_supervised!(TestRepo)
      assert SpecTemplates.request_opts(TestRepo, [])[:finch] == TestRepo.Finch
    end

    test "falls back to Req's default pool when the repo isn't running" do
      refute Keyword.has_key?(SpecTemplates.request_opts(TestRepo, []), :finch)
    end

    test "a :finch option wins over the repo's pool" do
      start_supervised!(TestRepo)
      assert SpecTemplates.request_opts(TestRepo, finch: MyFinch)[:finch] == MyFinch
    end
  end
end
