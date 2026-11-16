import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/wiki_explorer start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :wiki_explorer, WikiExplorerWeb.Endpoint, server: true
end

config :wiki_explorer, WikiExplorerWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Druid. The repo talks to the Router, which proxies SQL queries to the Broker
# and serves the lookups and task APIs used by `mix druid.setup`. The defaults
# match the docker-compose file in the root of the ecto_druid repo.
druid_host = System.get_env("DRUID_HOST", "localhost")
druid_port = String.to_integer(System.get_env("DRUID_PORT", "9888"))

config :wiki_explorer, WikiExplorer.DruidRepo,
  host: druid_host,
  port: druid_port,
  context: %{sqlTimeZone: "Etc/UTC"},
  # Rendered into priv/druid/tasks/wiki_edits.json.eex. Task requests go to
  # the repo's host and port, the Router.
  tasks: [
    assigns: %{
      wiki_edits_uri:
        System.get_env("WIKI_EDITS_URI", "https://druid.apache.org/data/wikipedia.json.gz")
    }
  ],
  lookups: [
    host: druid_host,
    port: druid_port,
    # Rendered into priv/druid/lookups/channel_languages.json.eex
    assigns: %{
      channel_languages: %{
        "#ar.wikipedia" => "Arabic",
        "#ca.wikipedia" => "Catalan",
        "#ceb.wikipedia" => "Cebuano",
        "#cs.wikipedia" => "Czech",
        "#de.wikipedia" => "German",
        "#el.wikipedia" => "Greek",
        "#en.wikipedia" => "English",
        "#es.wikipedia" => "Spanish",
        "#eu.wikipedia" => "Basque",
        "#fa.wikipedia" => "Persian",
        "#fi.wikipedia" => "Finnish",
        "#fr.wikipedia" => "French",
        "#he.wikipedia" => "Hebrew",
        "#hu.wikipedia" => "Hungarian",
        "#id.wikipedia" => "Indonesian",
        "#it.wikipedia" => "Italian",
        "#ja.wikipedia" => "Japanese",
        "#ko.wikipedia" => "Korean",
        "#nl.wikipedia" => "Dutch",
        "#no.wikipedia" => "Norwegian",
        "#pl.wikipedia" => "Polish",
        "#pt.wikipedia" => "Portuguese",
        "#ro.wikipedia" => "Romanian",
        "#ru.wikipedia" => "Russian",
        "#sh.wikipedia" => "Serbo-Croatian",
        "#sr.wikipedia" => "Serbian",
        "#sv.wikipedia" => "Swedish",
        "#tr.wikipedia" => "Turkish",
        "#uk.wikipedia" => "Ukrainian",
        "#vi.wikipedia" => "Vietnamese",
        "#zh.wikipedia" => "Chinese"
      }
    }
  ]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :wiki_explorer, WikiExplorerWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/wiki_explorer_web/router\.ex$",
        ~r"lib/wiki_explorer_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :wiki_explorer, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :wiki_explorer, WikiExplorerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :wiki_explorer, WikiExplorerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :wiki_explorer, WikiExplorerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
