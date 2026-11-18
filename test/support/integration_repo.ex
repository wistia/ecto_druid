defmodule Ecto.Adapters.Druid.IntegrationRepo do
  @moduledoc false

  # Shares TestRepo's config, but test_helper.exs starts it once for the whole
  # run, so async integration tests can share it. TestRepo is started and
  # stopped per test module, sometimes with custom config, so two of those
  # modules can't run at the same time.
  use Ecto.Repo,
    otp_app: :ecto_druid,
    adapter: Ecto.Adapters.Druid
end
