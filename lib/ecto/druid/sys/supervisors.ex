defmodule Ecto.Druid.Sys.Supervisors do
  @moduledoc """
  The `sys.supervisors` table: one row per supervisor.

      from s in Ecto.Druid.Sys.Supervisors,
        where: s.healthy == 0,
        select: %{id: s.supervisor_id, state: s.detailed_state}

  `spec` is decoded from JSON (see `Ecto.Druid.JSON`).

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#supervisors-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "sys"
  schema "supervisors" do
    field :supervisor_id, :string
    field :datasource, :string
    field :state, :string
    field :detailed_state, :string
    field :healthy, :integer
    field :type, :string
    field :source, :string
    field :suspended, :integer
    field :spec, Ecto.Druid.JSON
  end
end
