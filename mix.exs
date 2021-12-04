defmodule Cron.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hrzndhrn/cron"

  def project do
    [
      app: :cron,
      version: @version,
      elixir: "~> 1.11",
      name: "Cron",
      description: description(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      package: package(),
      preferred_cli_env: preferred_cli_env(),
      source_url: @source_url
    ]
  end

  def description do
    "Cron parses cron expressions and calculates execution timings."
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "Cron",
      formatters: ["html"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def preferred_cli_env do
    [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "test/support/plts/dialyzer.plt"},
      flags: [:unmatched_returns]
    ]
  end

  defp deps do
    [
      {:benchee, "~> 1.0.0", only: :dev},
      {:benchee_dsl, "~> 0.1.0", only: :dev},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false},
      {:prove, "~> 0.1", only: [:dev, :test]},
      {:stream_data, "~> 0.5", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      maintainers: ["Marcus Kruse"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
