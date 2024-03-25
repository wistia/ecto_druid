defmodule Ecto.Adapters.Druid.TestRepo do
  use Ecto.Repo,
    otp_app: :ecto_druid,
    adapter: Ecto.Adapters.Druid
end
