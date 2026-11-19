defmodule LookupQueryIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid

  import Ecto.Query
  import Ecto.Druid.Query.String, only: [lookup: 3]

  alias Ecto.Adapters.Druid.IntegrationRepo
  alias Ecto.Druid.TestLookups.IntegrationCountries, as: Countries

  require Countries

  @lookup Countries.__lookup__(:name)

  setup_all do
    # Create the lookup from a template that generates it from the schema,
    # and wait until the Broker has it
    assert [{status, _}] =
             Druid.Lookups.sync(IntegrationRepo,
               path: Path.expand("fixtures/lookup_schemas", __DIR__),
               assigns: %{countries: %{"US" => "United States", "IT" => "Italy"}},
               wait: true,
               timeout: 180_000
             )

    assert status in [:created, :updated, :unchanged]

    router = [host: "localhost", port: IntegrationRepo.config()[:lookups][:port]]

    on_exit(fn ->
      Druid.Client.Lookup.delete("__default", @lookup) |> Druid.Client.request(router)
    end)

    :ok
  end

  test "reads the lookup as a schema" do
    assert %Countries{code: "US", name: "United States"} = IntegrationRepo.get(Countries, "US")
    assert IntegrationRepo.get(Countries, "XX") == nil

    # Druid can't ORDER BY a non-time column on a plain scan
    assert IntegrationRepo.all(from c in Countries, select: {c.code, c.name}) |> Enum.sort() ==
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

    assert IntegrationRepo.all(query) == [
             {"RU", nil, "Unknown", "Unknown"},
             {"US", "United States", "United States", "United States"}
           ]
  end
end
