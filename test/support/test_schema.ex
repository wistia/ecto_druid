defmodule Ecto.Adapters.Druid.Wikipedia do
  use Ecto.Schema

  @primary_key false
  schema "wikipedia" do
    field :time, :utc_datetime_usec, source: :__time
    field :page, :string
    field :user, :string
    field :added, :integer
    field :deleted, :integer
    field :delta, :integer
  end

  def by_page(page) do
    import Ecto.Query
    import Ecto.Druid.Query

    from(
      m in __MODULE__,
      where: m.page == ^page,
      select: %{
        added: sum(m.added),
        deleted: sum(m.deleted),
        delta: sum(m.delta),
        unique_users: approx_count_distinct_ds_theta(m.user, 256),
        delta_histogram:
          ds_histogram(ds_quantiles_sketch(m.delta, 256), [-1000, -500, -200, 0, 200, 500, 1000])
      }
    )
  end
end
