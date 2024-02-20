defmodule Ecto.Adapters.Druid.MediaEvents do
  use Ecto.Schema

  @primary_key false
  schema "media_events" do
    field :time, :utc_datetime_usec, source: :__time
    field :account_id, :id
    field :media_id, :id
    field :loads, :integer
    field :plays, :integer
  end

  def by_media_id(account_id, media_id) do
    import Ecto.Query

    from(
      m in __MODULE__,
      where: m.account_id == ^account_id and m.media_id == ^media_id,
      select: %{
        account_id: m.account_id,
        media_id: m.media_id,
        loads: sum(m.loads),
        plays: sum(m.plays)
      }
    )
  end
end
