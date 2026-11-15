import Config

config :ecto_druid,
  use_logger: true,
  log_in_color: true

config :logger,
  compile_time_purge_level: :debug,
  level: :info

config :ecto_druid, Ecto.Adapters.Druid.TestRepo,
  host: "localhost",
  port: 9082,
  scheme: "http"

config :ecto_druid, Ecto.Adapters.Druid.TestRepo,
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
  ]
