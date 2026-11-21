defmodule Ecto.Adapters.Druid.StubRepo do
  @moduledoc false

  # A repo configured like an app's test repo, with `plug: {Req.Test, ...}`,
  # for the Ecto.Druid.Test tests. test_helper.exs starts it once.
  use Ecto.Repo,
    otp_app: :ecto_druid,
    adapter: Ecto.Adapters.Druid
end
