{:ok, _} = Ecto.Adapters.Druid.IntegrationRepo.start_link()
{:ok, _} = Ecto.Adapters.Druid.StubRepo.start_link()

# Tests tagged :druid need a running Druid; run them with
# `mix test --include druid`.
ExUnit.start(exclude: [:druid])
