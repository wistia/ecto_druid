defmodule Ecto.Druid.Lookup do
  @moduledoc """
  Defines an Ecto schema for a Druid [lookup](https://druid.apache.org/docs/latest/querying/lookups).

      defmodule MyApp.Countries do
        use Ecto.Druid.Lookup
      end

  Druid exposes each lookup as a table in the `lookup` schema with a key
  column `k` and a value column `v`. The schema above reads the `countries`
  lookup, named after the module, so it can be queried, joined and fetched by
  key like any other schema:

      MyApp.Repo.get(MyApp.Countries, "US")
      #=> %MyApp.Countries{k: "US", v: "United States"}

      from t in "page_views",
        left_join: c in MyApp.Countries,
        on: c.k == t.country,
        select: {t.country, c.v}

  Pass the module to `Ecto.Druid.Query.String.lookup/3` in place of the
  lookup's name to call Druid's `LOOKUP` function:

      from t in "page_views",
        group_by: 1,
        select: {lookup(t.country, MyApp.Countries, "Unknown"), count()}

  The module also defines `lookup/1` and `lookup/2` macros that do the same.
  `require` the module to use them: `MyApp.Countries.lookup(t.country,
  "Unknown")`.

  `LOOKUP` is usually faster than a join, and Druid can rewrite filters on it
  into filters on the key column.

  ## Options

    * `:name` - the lookup's name in Druid. Defaults to the last part of the
      module name, underscored (`MyApp.CountryNames` reads `country_names`).
    * `:key` - the name of the key field. Defaults to `:k`.
    * `:value` - the name of the value field. Defaults to `:v`.

  Renamed fields still read the `k` and `v` columns:

      defmodule MyApp.Countries do
        use Ecto.Druid.Lookup, key: :code, value: :name
      end

      MyApp.Repo.get(MyApp.Countries, "US")
      #=> %MyApp.Countries{code: "US", name: "United States"}

  The key is the schema's primary key. Lookups are read-only: change them
  with `Druid.Lookups` or `Druid.Client.Lookup`.
  """

  @doc false
  defmacro __using__(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    {key, opts} = Keyword.pop(opts, :key, :k)
    {value, opts} = Keyword.pop(opts, :value, :v)

    if opts != [] do
      raise ArgumentError,
            "unknown options for Ecto.Druid.Lookup: #{inspect(Keyword.keys(opts))}"
    end

    unless is_atom(key) and is_atom(value) do
      raise ArgumentError, "Ecto.Druid.Lookup :key and :value must be atoms"
    end

    name = name || default_name(__CALLER__.module)

    unless is_binary(name) and name != "" do
      raise ArgumentError, "Ecto.Druid.Lookup :name must be a non-empty string"
    end

    lookup_sql = "LOOKUP(?, '#{String.replace(name, "'", "''")}')"
    lookup_default_sql = "LOOKUP(?, '#{String.replace(name, "'", "''")}', ?)"

    quote do
      use Ecto.Schema

      @primary_key {unquote(key), :string, autogenerate: false, source: :k}
      @schema_prefix "lookup"
      schema unquote(name) do
        field unquote(value), :string, source: :v
      end

      @doc "Returns the name of this lookup in Druid."
      @spec __lookup__(:name) :: String.t()
      def __lookup__(:name), do: unquote(name)

      @doc """
      Maps `expr` through this lookup with Druid's `LOOKUP` function, giving
      `NULL` for keys that are not in it.
      """
      defmacro lookup(expr) do
        Ecto.Druid.Util.fragment(unquote(lookup_sql), [expr], nil)
      end

      @doc """
      Maps `expr` through this lookup with Druid's `LOOKUP` function, giving
      `default` for keys that are not in it.
      """
      defmacro lookup(expr, default) do
        Ecto.Druid.Util.fragment(unquote(lookup_default_sql), [expr, default], nil)
      end
    end
  end

  defp default_name(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end
end
