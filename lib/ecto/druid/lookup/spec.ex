defmodule Ecto.Druid.Lookup.Spec do
  @moduledoc """
  Builds a lookup's `lookupExtractorFactory` from a schema that uses
  `Ecto.Druid.Lookup`.

  `factory/2` returns a map ready to encode as JSON. Lookup templates have a
  `lookup_factory` helper that returns JSON (see
  `Druid.Supervisors.Template.Helpers`).
  """

  @map_opts [:map, :merge]
  @jdbc_opts [:connector, :poll_period, :first_cache_timeout, :merge]
  @connector_opts [:uri, :user, :password]

  @doc """
  Builds the `lookupExtractorFactory` for `schema`.

  The schema sets the lookup's type, its source table and columns, and
  whether it's injective (see `Ecto.Druid.Lookup`). The options supply what
  changes between environments.

  ## Options for map lookups

    * `:map` - the lookup's keys and values. Required.

  ## Options for JDBC lookups

    * `:connector` - a map or keyword list with the database's `:uri` (a JDBC
      URI, required), `:user` and `:password`. Give the password as
      `{:env, "VARIABLE"}` to have Druid read it from its own environment,
      which keeps it out of your config. A plain string is sent as is.
    * `:poll_period` - how often Druid reloads the table, as an ISO 8601
      period such as `"PT10M"`. Without it, Druid loads the table once.
    * `:first_cache_timeout` - milliseconds to wait for the first load before
      the lookup is usable.

  ## Options for both

    * `:merge` - a map deep-merged into the result, for anything else, for
      example `%{"extractionNamespace" => %{"jitterSeconds" => 60}}`.

  ## Examples

      Ecto.Druid.Lookup.Spec.factory(MyApp.Countries, map: %{"US" => "United States"})
      #=> %{"type" => "map", "map" => %{"US" => "United States"}}
  """
  @spec factory(module(), Keyword.t()) :: map()
  def factory(schema, opts \\ []) do
    unless lookup_schema?(schema) do
      raise ArgumentError,
            "#{inspect(schema)} is not a lookup schema; define it with `use Ecto.Druid.Lookup`"
    end

    {merge, opts} = Keyword.pop(opts, :merge, %{})

    schema
    |> build(schema.__lookup__(:source), opts)
    |> deep_merge(merge)
  end

  defp build(schema, nil, opts) do
    check_opts!(schema, opts, @map_opts, "map")

    map =
      Keyword.get(opts, :map) ||
        raise ArgumentError, "#{inspect(schema)} is a map lookup and needs the :map option"

    %{"type" => "map", "map" => Map.new(map)}
    |> put_if("isOneToOne", schema.__lookup__(:injective))
  end

  defp build(schema, {:jdbc, source}, opts) do
    check_opts!(schema, opts, @jdbc_opts, "JDBC")

    connector =
      Keyword.get(opts, :connector) ||
        raise ArgumentError, "#{inspect(schema)} is a JDBC lookup and needs the :connector option"

    namespace =
      %{
        "type" => "jdbc",
        "connectorConfig" => connector_config(schema, connector),
        "table" => source[:table],
        "keyColumn" => source[:key_column],
        "valueColumn" => source[:value_column]
      }
      |> put_if("filter", source[:filter])
      |> put_if("tsColumn", source[:ts_column])
      |> put_if("pollPeriod", opts[:poll_period])

    %{"type" => "cachedNamespace", "extractionNamespace" => namespace}
    |> put_if("firstCacheTimeout", opts[:first_cache_timeout])
    |> put_if("injective", schema.__lookup__(:injective))
  end

  defp connector_config(schema, connector) do
    connector = Map.new(connector)

    case Map.keys(connector) -- @connector_opts do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown :connector options: #{inspect(unknown)}"
    end

    uri =
      connector[:uri] ||
        raise ArgumentError, "#{inspect(schema)} :connector needs a :uri"

    %{"connectURI" => uri}
    |> put_if("user", connector[:user])
    |> put_if("password", password(connector[:password]))
  end

  defp password({:env, variable}) when is_binary(variable),
    do: %{"type" => "environment", "variable" => variable}

  defp password(password) when is_binary(password) or is_nil(password), do: password

  defp password(other) do
    raise ArgumentError,
          ":password must be a string or {:env, \"VARIABLE\"}, got: #{inspect(other)}"
  end

  defp check_opts!(schema, opts, allowed, kind) do
    case Keyword.keys(opts) -- allowed do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown options for #{inspect(schema)}, a #{kind} lookup: #{inspect(unknown)}. " <>
                "Expected: #{inspect(allowed)}"
    end
  end

  defp lookup_schema?(schema) do
    is_atom(schema) and Code.ensure_loaded?(schema) and
      function_exported?(schema, :__lookup__, 1)
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, _key, false), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = l, %{} = r -> deep_merge(l, r)
      _key, _l, r -> r
    end)
  end
end
