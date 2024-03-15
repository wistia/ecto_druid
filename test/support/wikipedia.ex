defmodule Ecto.Adapters.Druid.Wikipedia do
  use Ecto.Schema

  @primary_key false
  schema "wikipedia" do
    field :time, Ecto.Druid.DateTime, source: :__time
    field :page, :string
    field :user, :string
    field :added, :integer
    field :deleted, :integer
    field :delta, :integer
  end

  def by_page(page) do
    import Ecto.Query

    import Ecto.Druid.Query,
      only: [
        ds_theta: 2,
        approx_count_distinct_ds_theta: 2,
        ds_quantiles_sketch: 2,
        ds_histogram: 2
      ]

    from(
      m in __MODULE__,
      where: m.page == ^page,
      select: %{
        added: sum(m.added),
        deleted: sum(m.deleted),
        delta: sum(m.delta),
        unique_users: approx_count_distinct_ds_theta(m.user, 256),
        delta_histogram:
          m.delta
          |> ds_quantiles_sketch(256)
          |> ds_histogram([-30, -20, -10, 0, 10, 20, 30]),
        ds_theta: ds_theta(m.user, 256)
      }
    )
  end

  def over_time(time_range) do
    import Ecto.Query

    import Ecto.Druid.Query,
      only: [
        ds_theta: 2,
        approx_count_distinct_ds_theta: 2,
        ds_quantiles_sketch: 2,
        ds_histogram: 2,
        time_in_interval: 2
      ]

    from(
      m in __MODULE__,
      where: time_in_interval(m.time, ^time_range),
      select: %{
        time: m.time,
        page: m.page,
        added: sum(m.added),
        deleted: sum(m.deleted),
        delta: sum(m.delta),
        unique_users: approx_count_distinct_ds_theta(m.user, 256),
        delta_histogram:
          m.delta
          |> ds_quantiles_sketch(256)
          |> ds_histogram([-30, -20, -10, 0, 10, 20, 30]),
        ds_theta: ds_theta(m.user, 256)
      },
      group_by: [m.time, m.page],
      limit: 3
    )
  end
end
