defmodule Ecto.Druid.Sys.ServerProperties do
  @moduledoc """
  The `sys.server_properties` table: the runtime properties of each server.

      from p in Ecto.Druid.Sys.ServerProperties,
        where: p.property == "druid.service",
        select: {p.server, p.value}

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#server_properties-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "sys"
  schema "server_properties" do
    field :server, :string
    field :service_name, :string
    field :node_roles, :string
    field :property, :string
    field :value, :string
    field :error_message, :string
  end
end
