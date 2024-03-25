defmodule Ecto.Adapters.Druid.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wistia/ecto_druid"

  def project do
    [
      app: :ecto_adapters_druid,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
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
      {:req, "~> 0.4.9"},
      {:jason, "~> 1.0"},
      {:plug, "~> 1.15", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Ecto.Adapters.Druid",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/ecto_druid",
      source_url: @source_url,
      groups_for_modules: [
        Querying: [
          Ecto.Druid.Query
        ],
        "Druid Ecto Types": [
          Ecto.Druid.DateTime,
          Ecto.Druid.DSHistogram,
          Ecto.Druid.HLLSketch,
          Ecto.Druid.QuantilesSketch,
          Ecto.Druid.ThetaSketch,
          Ecto.Druid.TupleSketch
        ],
        "Druid Client": [
          Druid.Client,
          Druid.Client.SQL,
          Druid.Client.Native,
          Druid.Client.Task
        ],
        Utilities: [
          Ecto.Druid.ComplexType,
          Ecto.Druid.Util
        ]
      ]
    ]
  end
end
