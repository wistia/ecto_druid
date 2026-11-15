defmodule Ecto.Druid.Sys.Tasks do
  @moduledoc """
  The `sys.tasks` table: running, pending, waiting and recently completed
  ingestion tasks.

      from t in Ecto.Druid.Sys.Tasks,
        where: t.status == "FAILED",
        order_by: [desc: t.created_time],
        select: %{task_id: t.task_id, datasource: t.datasource, error: t.error_msg}

  `duration` is in milliseconds.

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#tasks-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "sys"
  schema "tasks" do
    field :task_id, :string
    field :group_id, :string
    field :type, :string
    field :datasource, :string
    field :created_time, Ecto.Druid.DateTime
    field :queue_insertion_time, Ecto.Druid.DateTime
    field :status, :string
    field :runner_status, :string
    field :duration, :integer
    field :location, :string
    field :host, :string
    field :plaintext_port, :integer
    field :tls_port, :integer
    field :error_msg, :string
  end
end
