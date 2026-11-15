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
    * `:injective` - whether each value belongs to only one key. Druid can
      then rewrite queries on `LOOKUP` more aggressively. Defaults to `false`.
    * `:jdbc` - load the lookup from a database table. See "Defining the
      lookup" below. Without it, the lookup is a map lookup.

  Renamed fields still read the `k` and `v` columns:

      defmodule MyApp.Countries do
        use Ecto.Druid.Lookup, key: :code, value: :name
      end

      MyApp.Repo.get(MyApp.Countries, "US")
      #=> %MyApp.Countries{code: "US", name: "United States"}

  The key is the schema's primary key. Lookups are read-only through Ecto.

  ## Defining the lookup

  The schema also describes how the lookup is loaded, so a lookup template
  (see `Druid.Lookups`) can generate its `lookupExtractorFactory` with the
  `lookup_factory` helper, the way supervisor templates use `data_schema`.
  The schema holds what stays the same everywhere. The template passes what
  changes between environments, from assigns.

  A map lookup takes its values from the template:

      # priv/druid/lookups/countries.json.eex
      <%= lookup_factory MyApp.Countries, map: @countries %>

  A JDBC lookup names its table in the schema, and its connection in the
  template:

      defmodule MyApp.Countries do
        use Ecto.Druid.Lookup,
          key: :code,
          value: :name,
          injective: true,
          jdbc: [table: "countries"]
      end

      # priv/druid/lookups/countries.json.eex
      <%= lookup_factory MyApp.Countries,
            connector: @lookup_db,
            poll_period: "PT10M" %>

  `:jdbc` takes:

    * `:table` - required.
    * `:key_column` - defaults to the key field's name (`"code"` above).
    * `:value_column` - defaults to the value field's name (`"name"` above).
    * `:filter` - a SQL `WHERE` condition limiting the rows loaded.
    * `:ts_column` - a last-modified column, so Druid only reloads changed
      rows.

  See `Ecto.Druid.Lookup.Spec.factory/2` for the template options.
  """

  @jdbc_opts [:table, :key_column, :value_column, :filter, :ts_column]

  @doc false
  defmacro __using__(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    {key, opts} = Keyword.pop(opts, :key, :k)
    {value, opts} = Keyword.pop(opts, :value, :v)
    {injective, opts} = Keyword.pop(opts, :injective, false)
    {jdbc, opts} = Keyword.pop(opts, :jdbc)

    if opts != [] do
      raise ArgumentError,
            "unknown options for Ecto.Druid.Lookup: #{inspect(Keyword.keys(opts))}"
    end

    unless is_atom(key) and is_atom(value) do
      raise ArgumentError, "Ecto.Druid.Lookup :key and :value must be atoms"
    end

    unless is_boolean(injective) do
      raise ArgumentError, "Ecto.Druid.Lookup :injective must be a boolean"
    end

    source = if jdbc, do: {:jdbc, jdbc_source(jdbc, key, value)}

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
      @doc """
      Returns information about this lookup:

        * `:name` - its name in Druid.
        * `:injective` - whether each value belongs to only one key.
        * `:source` - `nil` for a map lookup, or `{:jdbc, opts}` with the
          `:jdbc` options, column defaults filled in.
      """
      @spec __lookup__(:name | :injective | :source) :: term()
      def __lookup__(:name), do: unquote(name)
      def __lookup__(:injective), do: unquote(injective)
      def __lookup__(:source), do: unquote(Macro.escape(source))

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

  defp jdbc_source(jdbc, key, value) do
    unless Keyword.keyword?(jdbc) do
      raise ArgumentError, "Ecto.Druid.Lookup :jdbc must be a literal keyword list"
    end

    case Keyword.keys(jdbc) -- @jdbc_opts do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown :jdbc options: #{inspect(unknown)}"
    end

    for {opt, val} <- jdbc, not is_binary(val) do
      raise ArgumentError, "Ecto.Druid.Lookup :jdbc option #{inspect(opt)} must be a string"
    end

    unless Keyword.has_key?(jdbc, :table) do
      raise ArgumentError, "Ecto.Druid.Lookup :jdbc requires :table"
    end

    jdbc
    |> Keyword.put_new(:key_column, Atom.to_string(key))
    |> Keyword.put_new(:value_column, Atom.to_string(value))
  end

  defp default_name(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end
end
