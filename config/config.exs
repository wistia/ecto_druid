import Config

config :ecto_adapters_druid,
  use_logger: true,
  log_in_color: true

config :logger,
  compile_time_purge_level: :debug,
  level: :info

config :ecto_adapters_druid, Ecto.Adapters.Druid.TestRepo,
  host: "localhost",
  port: 9082,
  scheme: "http"
