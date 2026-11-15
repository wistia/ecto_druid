defmodule Ecto.Druid.Lookup.SpecTest do
  use ExUnit.Case, async: true

  alias Ecto.Druid.Lookup.Spec
  alias Ecto.Druid.TestLookups.{Countries, CountryNames, JdbcCountries}

  describe "schema options" do
    test "default to a non-injective map lookup" do
      assert Countries.__lookup__(:source) == nil
      assert Countries.__lookup__(:injective) == false
    end

    test "jdbc columns default to the field names" do
      defaults = Ecto.Druid.TestLookups.JdbcCountries.__lookup__(:source)

      assert {:jdbc, opts} = defaults
      assert opts[:key_column] == "code"
      assert opts[:value_column] == "name"
      assert opts[:table] == "countries"
    end

    test "raise on bad jdbc options" do
      for {jdbc, message} <- [
            {"[key_column: \"code\"]", ~r/:jdbc requires :table/},
            {"[table: \"t\", columns: \"x\"]", ~r/unknown :jdbc options: \[:columns\]/},
            {"[table: :t]", ~r/:table must be a string/}
          ] do
        assert_raise ArgumentError, message, fn ->
          Code.eval_string("""
          defmodule Ecto.Druid.Lookup.SpecTest.Bad do
            use Ecto.Druid.Lookup, jdbc: #{jdbc}
          end
          """)
        end
      end
    end

    test "raise on a non-boolean injective" do
      assert_raise ArgumentError, ~r/:injective must be a boolean/, fn ->
        Code.eval_string("""
        defmodule Ecto.Druid.Lookup.SpecTest.Bad do
          use Ecto.Druid.Lookup, injective: "yes"
        end
        """)
      end
    end
  end

  describe "factory/2 for map lookups" do
    test "builds a map factory" do
      assert Spec.factory(Countries, map: %{"US" => "United States"}) ==
               %{"type" => "map", "map" => %{"US" => "United States"}}
    end

    test "accepts a keyword list and merges extra fields" do
      assert Spec.factory(CountryNames, map: [US: "United States"], merge: %{"extra" => 1}) ==
               %{"type" => "map", "map" => %{US: "United States"}, "extra" => 1}
    end

    test "requires :map and rejects JDBC options" do
      assert_raise ArgumentError, ~r/map lookup and needs the :map option/, fn ->
        Spec.factory(Countries)
      end

      assert_raise ArgumentError, ~r/unknown options .* a map lookup: \[:connector\]/, fn ->
        Spec.factory(Countries, map: %{}, connector: [uri: "jdbc:x"])
      end
    end
  end

  describe "factory/2 for JDBC lookups" do
    test "builds a cachedNamespace factory" do
      assert Spec.factory(JdbcCountries,
               connector: %{uri: "jdbc:postgresql://db/app", user: "druid"},
               poll_period: "PT10M",
               first_cache_timeout: 60_000
             ) == %{
               "type" => "cachedNamespace",
               "extractionNamespace" => %{
                 "type" => "jdbc",
                 "connectorConfig" => %{
                   "connectURI" => "jdbc:postgresql://db/app",
                   "user" => "druid"
                 },
                 "table" => "countries",
                 "keyColumn" => "code",
                 "valueColumn" => "name",
                 "filter" => "active = true",
                 "tsColumn" => "updated_at",
                 "pollPeriod" => "PT10M"
               },
               "firstCacheTimeout" => 60_000,
               "injective" => true
             }
    end

    test "reads the password from Druid's environment" do
      factory =
        Spec.factory(JdbcCountries,
          connector: [uri: "jdbc:x", password: {:env, "LOOKUP_DB_PASSWORD"}]
        )

      assert factory["extractionNamespace"]["connectorConfig"]["password"] ==
               %{"type" => "environment", "variable" => "LOOKUP_DB_PASSWORD"}
    end

    test "deep-merges :merge" do
      factory =
        Spec.factory(JdbcCountries,
          connector: [uri: "jdbc:x"],
          merge: %{"extractionNamespace" => %{"jitterSeconds" => 60}}
        )

      assert factory["extractionNamespace"]["jitterSeconds"] == 60
      assert factory["extractionNamespace"]["table"] == "countries"
    end

    test "validates the connector" do
      assert_raise ArgumentError, ~r/needs the :connector option/, fn ->
        Spec.factory(JdbcCountries)
      end

      assert_raise ArgumentError, ~r/:connector needs a :uri/, fn ->
        Spec.factory(JdbcCountries, connector: [user: "druid"])
      end

      assert_raise ArgumentError, ~r/unknown :connector options: \[:url\]/, fn ->
        Spec.factory(JdbcCountries, connector: [url: "jdbc:x"])
      end

      assert_raise ArgumentError, ~r/:password must be a string/, fn ->
        Spec.factory(JdbcCountries, connector: [uri: "jdbc:x", password: {:file, "x"}])
      end
    end
  end

  test "rejects a module that is not a lookup schema" do
    assert_raise ArgumentError, ~r/Enum is not a lookup schema/, fn ->
      Spec.factory(Enum, map: %{})
    end
  end
end
