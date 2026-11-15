defmodule Ecto.Druid.Sys.Servers do
  @moduledoc """
  The `sys.servers` table: one row per discovered Druid server.

      from s in Ecto.Druid.Sys.Servers,
        where: s.server_type == "historical",
        select: %{server: s.server, tier: s.tier, curr_size: s.curr_size, max_size: s.max_size}

  `labels` is decoded from JSON (see `Ecto.Druid.JSON`).

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#servers-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "sys"
  schema "servers" do
    field :server, :string
    field :host, :string
    field :plaintext_port, :integer
    field :tls_port, :integer
    field :server_type, :string
    field :tier, :string
    field :curr_size, :integer
    field :max_size, :integer
    field :storage_size, :integer
    field :is_leader, :integer
    field :start_time, Ecto.Druid.DateTime
    field :version, :string
    field :build_revision, :string
    field :labels, Ecto.Druid.JSON
    field :available_processors, :integer
    field :total_memory, :integer
  end
end
