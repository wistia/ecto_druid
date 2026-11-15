defmodule Ecto.Druid.TestLookups.Countries do
  @moduledoc false
  use Ecto.Druid.Lookup
end

defmodule Ecto.Druid.TestLookups.CountryNames do
  @moduledoc false
  use Ecto.Druid.Lookup, name: "country_names_v2", key: :code, value: :name
end

defmodule Ecto.Druid.TestLookups.IntegrationCountries do
  @moduledoc false
  use Ecto.Druid.Lookup, name: "ecto_druid_lookup_query_test", key: :code, value: :name
end

defmodule Ecto.Druid.TestLookups.JdbcCountries do
  @moduledoc false
  use Ecto.Druid.Lookup,
    name: "countries",
    key: :code,
    value: :name,
    injective: true,
    jdbc: [table: "countries", filter: "active = true", ts_column: "updated_at"]
end
