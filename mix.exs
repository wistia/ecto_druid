defmodule Ecto.Adapters.Druid.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/wistia/ecto_druid"

  def project do
    [
      app: :ecto_druid,
      description: "Ecto adapter for Druid",
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs(),
      aliases: [publish: ["hex.publish", &git_tag/1]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.7"},
      {:req, "~> 0.5.8"},
      {:jason, "~> 1.0"},
      {:plug, "~> 1.15", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Allen Madsen", "Garrett Schroath", "Konstantin Minevskiy", "Wistia"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/ecto_druid"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/getting_started.md",
        "guides/querying.md",
        "guides/native_queries.md",
        "guides/ingestion_specs.md",
        "guides/compaction_retention_lookups.md",
        "guides/system_tables.md",
        "guides/druid_client.md",
        "guides/upgrading.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/[^\/]+\.md/
      ],
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/ecto_druid",
      source_url: @source_url,
      groups_for_modules: [
        Querying: [
          Ecto.Druid.Query,
          Ecto.Druid.Query.Numeric,
          Ecto.Druid.Query.String,
          Ecto.Druid.Query.DateTime,
          Ecto.Druid.Interval,
          Ecto.Druid.Query.Reduction,
          Ecto.Druid.Query.IP,
          Ecto.Druid.Query.Scalar,
          Ecto.Druid.Query.Aggregations,
          Ecto.Druid.Query.HLL,
          Ecto.Druid.Query.Theta,
          Ecto.Druid.Query.Quantiles,
          Ecto.Druid.Query.Tuple,
          Ecto.Druid.Query.TDigest,
          Ecto.Druid.Query.Array,
          Ecto.Druid.Query.MultiValue,
          Ecto.Druid.Query.JSON,
          Ecto.Druid.Query.Table
        ],
        "Druid Ecto Types": [
          Ecto.Druid.DateTime,
          Ecto.Druid.DSHistogram,
          Ecto.Druid.HLLSketch,
          Ecto.Druid.QuantilesSketch,
          Ecto.Druid.ThetaSketch,
          Ecto.Druid.TupleSketch,
          Ecto.Druid.JSON
        ],
        "System Tables": [
          Ecto.Druid.Sys.Segments,
          Ecto.Druid.Sys.ServerSegments,
          Ecto.Druid.Sys.Servers,
          Ecto.Druid.Sys.ServerProperties,
          Ecto.Druid.Sys.Tasks,
          Ecto.Druid.Sys.Supervisors,
          Ecto.Druid.InformationSchema.Schemata,
          Ecto.Druid.InformationSchema.Tables,
          Ecto.Druid.InformationSchema.Columns,
          Ecto.Druid.InformationSchema.Routines
        ],
        "Druid Client": [
          Druid.Client,
          Druid.Client.SQL,
          Druid.Client.Native,
          Druid.Client.Task,
          Druid.Client.Supervisor,
          Druid.Client.Compaction,
          Druid.Client.Retention,
          Druid.Client.Lookup
        ],
        "Supervisor Specs": [
          Ecto.Druid.Schema,
          Ecto.Druid.Schema.Spec,
          Druid.Supervisors,
          Druid.Supervisors.Spec,
          Druid.Supervisors.Template,
          Druid.Supervisors.Template.Helpers,
          Druid.Compaction,
          Druid.Compaction.Config,
          Druid.Retention,
          Druid.Retention.Rules,
          Druid.Lookups,
          Druid.Lookups.Lookup
        ],
        Utilities: [
          Ecto.Druid.ComplexType,
          Ecto.Druid.Util
        ]
      ]
    ]
  end

  defp git_tag(_args) do
    tag = "v" <> Mix.Project.config()[:version]
    System.cmd("git", ["tag", tag])
    System.cmd("git", ["push", "origin", tag])
  end
end
