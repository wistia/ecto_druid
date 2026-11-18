defmodule Druid.LookupsAwaitTest do
  use ExUnit.Case, async: true
  alias Druid.Lookups
  alias Druid.Lookups.Lookup
  alias Ecto.Adapters.Druid.TestRepo

  @moduletag :tmp_dir

  # Answers each lookup's status requests with its statuses in turn,
  # repeating the last. A status of 404 answers with a 404. Requests are sent
  # to the test process.
  defp druid(statuses, opts \\ []) do
    test_pid = self()
    {:ok, agent} = Agent.start_link(fn -> statuses end)
    current = Keyword.get(opts, :current, %{})

    fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      case {conn.method, conn.path_info} do
        {"GET", [_, _, _, "lookups", "status", tier, name]} ->
          send(test_pid, {:status, tier, name, conn.query_string})

          case next(agent, "#{tier}/#{name}") do
            404 -> conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "not found"})
            status -> Req.Test.json(conn, status)
          end

        {"GET", [_, _, _, "lookups", "config", "all"]} ->
          Req.Test.json(conn, current)

        {"POST", [_, _, _, "lookups", "config", _tier, _name]} ->
          conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{})
      end
    end
  end

  defp next(agent, key) do
    Agent.get_and_update(agent, fn statuses ->
      case Map.fetch!(statuses, key) do
        [last] -> {last, statuses}
        [status | rest] -> {status, Map.put(statuses, key, rest)}
      end
    end)
  end

  defp loaded, do: %{"loaded" => true, "pendingNodes" => []}
  defp pending(nodes), do: %{"loaded" => false, "pendingNodes" => nodes}

  describe "await/3" do
    test "waits until every lookup is loaded" do
      plug =
        druid(%{
          "__default/countries" => [pending(["broker:8082"]), loaded()],
          "realtime/channels" => [pending(["peon:8100"]), pending(["peon:8100"]), loaded()]
        })

      assert :ok =
               Lookups.await(TestRepo, ["countries", {"realtime", "channels"}],
                 plug: plug,
                 poll_interval: 1
               )

      assert_received {:status, "__default", "countries", "detailed=true"}
      assert_received {:status, "realtime", "channels", "detailed=true"}
    end

    test "takes rendered lookups, tier/name strings, and the configured tier" do
      plug =
        druid(%{
          "__default/a" => [loaded()],
          "realtime/b" => [loaded()],
          "other/c" => [loaded()]
        })

      lookup = %Lookup{name: "a", tier: "__default", lookup: "a"}
      assert :ok = Lookups.await(TestRepo, [lookup, "realtime/b"], plug: plug)
      assert :ok = Lookups.await(TestRepo, ["c"], plug: plug, tier: "other")
    end

    test "returns :ok for no lookups without asking Druid" do
      assert :ok = Lookups.await(TestRepo, [], plug: fn _conn -> flunk("no request expected") end)
    end

    test "times out with the lookups and nodes still pending" do
      plug =
        druid(%{
          "__default/countries" => [pending(["broker:8082", "historical:8083"])],
          "__default/done" => [loaded()]
        })

      assert {:error, %Lookups.Error{reason: :timeout, pending: pending} = error} =
               Lookups.await(TestRepo, ["countries", "done"],
                 plug: plug,
                 poll_interval: 5,
                 timeout: 20
               )

      assert pending == %{"__default/countries" => ["broker:8082", "historical:8083"]}

      assert Exception.message(error) ==
               "timed out waiting for lookups to load: " <>
                 "__default/countries (not yet on broker:8082, historical:8083)"
    end

    test "returns request errors, such as for a lookup that doesn't exist" do
      plug = druid(%{"__default/missing" => [404]})

      assert {:error, %Druid.Client.RequestError{status: 404}} =
               Lookups.await(TestRepo, ["missing"], plug: plug)
    end
  end

  describe "sync/2 with wait: true" do
    @map_lookup """
    {"type": "map", "map": <%= json @values %>}
    """

    defp write!(dir, name) do
      File.write!(Path.join(dir, name <> ".json.eex"), @map_lookup)
    end

    defp opts(dir, plug, extra) do
      [path: dir, assigns: %{values: %{"US" => "United States"}}, plug: plug, wait: true] ++
        extra
    end

    test "waits for created, updated and unchanged lookups", %{tmp_dir: dir} do
      for name <- ["a", "b"], do: write!(dir, name)

      current = %{
        "__default" => %{
          "b" => %{
            "version" => "v1",
            "lookupExtractorFactory" => %{"type" => "map", "map" => %{"US" => "United States"}}
          }
        }
      }

      plug =
        druid(
          %{"__default/a" => [pending(["broker:8082"]), loaded()], "__default/b" => [loaded()]},
          current: current
        )

      assert [{:created, %Lookup{lookup: "a"}}, {:unchanged, %Lookup{lookup: "b"}}] =
               Lookups.sync(TestRepo, opts(dir, plug, poll_interval: 1))

      assert_received {:status, "__default", "a", _}
      assert_received {:status, "__default", "b", _}
    end

    test "returns the lookups that didn't load as errors", %{tmp_dir: dir} do
      for name <- ["a", "b"], do: write!(dir, name)
      plug = druid(%{"__default/a" => [pending(["broker:8082"])], "__default/b" => [loaded()]})

      assert [{:error, %Lookup{lookup: "a"}, error}, {:created, %Lookup{lookup: "b"}}] =
               Lookups.sync(TestRepo, opts(dir, plug, poll_interval: 5, timeout: 20))

      assert %Lookups.Error{reason: :timeout, pending: %{"__default/a" => ["broker:8082"]}} =
               error
    end

    test "doesn't wait in dry-run mode", %{tmp_dir: dir} do
      write!(dir, "a")
      plug = druid(%{})

      assert [{:would_create, _}] = Lookups.sync(TestRepo, opts(dir, plug, dry_run: true))
      refute_received {:status, _, _, _}
    end
  end
end
