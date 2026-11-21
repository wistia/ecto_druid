defmodule Ecto.Druid.LookupTest do
  use ExUnit.Case

  import Ecto.Query
  import Ecto.Druid.Query.String, only: [lookup: 2, lookup: 3]

  alias Ecto.Adapters.Druid.TestRepo

  alias Ecto.Druid.TestLookups.{Countries, CountryNames}

  require Countries
  require CountryNames

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  test "names the lookup after the module by default" do
    assert Countries.__lookup__(:name) == "countries"
    assert Countries.__schema__(:source) == "countries"
    assert Countries.__schema__(:prefix) == "lookup"
    assert Countries.__schema__(:fields) == [:k, :v]
    assert Countries.__schema__(:primary_key) == [:k]
  end

  test "selects from the lookup schema" do
    query = from c in Countries, select: {c.k, c.v}

    assert TestRepo.to_sql(query) ==
             {~s|SELECT c0."k", c0."v" FROM "lookup"."countries" AS c0|, []}
  end

  test "renamed fields read the k and v columns" do
    query = from c in CountryNames, where: c.code == ^"US", select: c

    assert TestRepo.to_sql(query) ==
             {~s|SELECT c0."k", c0."v" FROM "lookup"."country_names_v2" AS c0 | <>
                ~s|WHERE (c0."k" = ?)|, ["US"]}
  end

  test "joins a datasource to the lookup" do
    query =
      from t in "test",
        left_join: c in Countries,
        on: c.k == t.country,
        select: {t.country, c.v}

    assert TestRepo.to_sql(query) ==
             {~s|SELECT t0."country", c1."v" FROM "test" AS t0 | <>
                ~s|LEFT OUTER JOIN "lookup"."countries" AS c1 ON c1."k" = t0."country"|, []}
  end

  test "lookup/1 and lookup/2 call LOOKUP with the lookup's name" do
    query =
      from t in "test",
        where: Countries.lookup(t.country) == "United States",
        select: CountryNames.lookup(t.country, ^"Unknown")

    assert TestRepo.to_sql(query) ==
             {~s|SELECT LOOKUP(t0."country", 'country_names_v2', ?) FROM "test" AS t0 | <>
                ~s|WHERE (LOOKUP(t0."country", 'countries') = 'United States')|, ["Unknown"]}
  end

  test "LOOKUP accepts a lookup schema module as the name" do
    query =
      from t in "test",
        where: lookup(t.country, Countries) == "United States",
        select: lookup(t.country, CountryNames, ^"Unknown")

    assert TestRepo.to_sql(query) ==
             {~s|SELECT LOOKUP(t0."country", 'country_names_v2', ?) FROM "test" AS t0 | <>
                ~s|WHERE (LOOKUP(t0."country", 'countries') = 'United States')|, ["Unknown"]}
  end

  test "LOOKUP rejects a module that is not a lookup schema" do
    assert_raise ArgumentError, ~r/Enum is not a lookup schema/, fn ->
      Code.eval_string("""
      import Ecto.Query
      import Ecto.Druid.Query.String, only: [lookup: 2]
      from t in "test", select: lookup(t.country, Enum)
      """)
    end
  end

  test "rejects unknown options" do
    assert_raise ArgumentError, ~r/unknown options.*:tier/, fn ->
      Code.eval_string("""
      defmodule Ecto.Druid.LookupTest.Bad do
        use Ecto.Druid.Lookup, tier: "realtime"
      end
      """)
    end
  end
end
