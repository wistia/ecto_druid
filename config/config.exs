import Config

config :logger, level: :info

# IntegrationRepo is a second repo for the async integration tests
for repo <- [Ecto.Adapters.Druid.TestRepo, Ecto.Adapters.Druid.IntegrationRepo] do
  config :ecto_druid, repo,
    host: "localhost",
    port: 9082,
    scheme: "http"

  config :ecto_druid, repo,
    supervisors: [
      # The supervisor API is on the router, not the broker
      port: 9888,
      path: Path.expand("../test/fixtures/supervisors", __DIR__),
      assigns: %{
        topic: "ecto_druid_supervisors_test",
        # Nothing listens here; the supervisor is created suspended
        consumer_properties: %{"bootstrap.servers" => "localhost:1"},
        task_count: 1
      }
    ],
    # The rules and lookups APIs are on the router too
    retention: [
      port: 9888,
      path: Path.expand("../test/fixtures/retention", __DIR__),
      assigns: %{tier: "_default_tier", replicas: 1, keep: "P2Y"}
    ],
    lookups: [
      port: 9888,
      path: Path.expand("../test/fixtures/lookups", __DIR__),
      assigns: %{countries: %{"US" => "United States", "CA" => "Canada"}}
    ],
    compaction: [
      port: 9888,
      path: Path.expand("../test/fixtures/compaction", __DIR__),
      assigns: %{target_rows: 5_000_000, skip_offset: "P1D"}
    ],
    # The tasks API is on the router too
    tasks: [
      port: 9888,
      path: Path.expand("../test/fixtures/tasks", __DIR__),
      assigns: %{max_parse_exceptions: 0}
    ],
    # Backfills use the :tasks host, port and assigns
    backfills: [
      path: Path.expand("../test/fixtures/backfills", __DIR__)
    ]
end

# StubRepo's requests go to Ecto.Druid.Test stubs, the way an app's tests
# would send them. Nothing listens on this host.
config :ecto_druid, Ecto.Adapters.Druid.StubRepo,
  host: "druid.example.com",
  port: 8888,
  plug: {Req.Test, Ecto.Adapters.Druid.StubRepo}
