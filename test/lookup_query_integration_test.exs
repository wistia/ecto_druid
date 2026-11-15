defmodule LookupQueryIntegrationTest do
  use ExUnit.Case

  import Ecto.Query
  import Ecto.Druid.Query.String, only: [lookup: 3]

  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Druid.TestLookups.IntegrationCountries, as: Countries

  require Countries

  @druid [host: "localhost", port: 9888]
  @lookup Countries.__lookup__(:name)

  # Druid pushes new lookups to Brokers on a timer (two minutes by default),
  # so wait for the Broker to see it rather than for the Coordinator's status.
  @load_timeout_s 180

  setup_all do
    Druid.Client.Lookup.initialize() |> Druid.Client.request(@druid)

    Druid.Client.Lookup.set("__default", @lookup, "v1", %{
      "type" => "map",
      "map" => %{"US" => "United States", "IT" => "Italy"}
    })
    |> Druid.Client.request!(@druid)

    on_exit(fn ->
      Druid.Client.Lookup.delete("__default", @lookup) |> Druid.Client.request(@druid)
    end)

    {:ok, _} = TestRepo.start_link()
    wait_until_loaded(@load_timeout_s)
    :ok
  end

  test "reads the lookup as a schema" do
    assert %Countries{code: "US", name: "United States"} = TestRepo.get(Countries, "US")
    assert TestRepo.get(Countries, "XX") == nil

    # Druid can't ORDER BY a non-time column on a plain scan
    assert TestRepo.all(from c in Countries, select: {c.code, c.name}) |> Enum.sort() ==
             [{"IT", "Italy"}, {"US", "United States"}]
  end

  test "joins a datasource to the lookup and maps values with LOOKUP" do
    query =
      from w in "wikipedia",
        left_join: c in Countries,
        on: c.code == w.countryIsoCode,
        where: w.countryIsoCode in ["US", "RU"],
        group_by: [w.countryIsoCode, c.name],
        order_by: w.countryIsoCode,
        select: {
          w.countryIsoCode,
          c.name,
          Countries.lookup(w.countryIsoCode, "Unknown"),
          lookup(w.countryIsoCode, Countries, "Unknown")
        }

    assert TestRepo.all(query) == [
             {"RU", nil, "Unknown", "Unknown"},
             {"US", "United States", "United States", "United States"}
           ]
  end

  defp wait_until_loaded(0), do: flunk("lookup #{@lookup} never reached the Broker")

  defp wait_until_loaded(tries) do
    if loaded?() do
      :ok
    else
      Process.sleep(1000)
      wait_until_loaded(tries - 1)
    end
  end

  defp loaded? do
    TestRepo.all(from c in Countries, select: count()) == [2]
  rescue
    _ -> false
  end
end
