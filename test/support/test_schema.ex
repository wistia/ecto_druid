defmodule Ecto.Adapters.Druid.ConversionEvents do
  use Ecto.Schema

  @primary_key false
  schema "conversion_events" do
    field :time, :utc_datetime_usec, source: :__time
    field :account_id, :id
    field :page_id, :id
    field :loads, :integer
    field :conversions, :integer
  end

  def by_page_id(account_id, page_id) do
    import Ecto.Query

    from(
      m in __MODULE__,
      where: m.account_id == ^account_id and m.page_id == ^page_id,
      select: %{
        account_id: m.account_id,
        page_id: m.page_id,
        loads: sum(m.loads),
        conversions: sum(m.conversions)
      }
    )
  end
end
