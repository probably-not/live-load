defmodule LiveLoad.MixProject do
  use Mix.Project

  @version "0.0.1-rc.33"
  @source_url "https://github.com/probably-not/live-load"
  @homepage_url @source_url

  def project do
    [
      app: :live_load,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_path(Mix.env()),
      deps: deps(),
      name: "LiveLoad",
      description:
        "./README.md"
        |> Path.expand()
        |> File.read!()
        |> String.split("<!-- HEX PACKAGE DESCRIPTION START -->")
        |> Enum.at(1)
        |> String.split("<!-- HEX PACKAGE DESCRIPTION END -->")
        |> List.first()
        |> String.trim(),
      source_url: @source_url,
      homepage_url: @homepage_url,
      package: [
        maintainers: ["Coby Benveniste"],
        licenses: ["MIT"],
        links: %{"GitHub" => @source_url, "Home Page" => @homepage_url},
        files: ["lib", "priv", "mix.exs", "README*", "LICENSE*", "CHANGELOG*", "DEVLOG*"]
      ],
      aliases: aliases(),
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"},
        plt_core_path: "priv/plts/core.plt",
        plt_add_deps: :app_tree,
        plt_add_apps: [:amoc],
        ignore_warnings: ".dialyzer.ignore-warnings.exs"
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      default_env: :dev,
      preferred_envs: [
        ci: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_path(:test), do: ["lib/", "test/support", "bench/"]
  defp elixirc_path(:dev), do: ["lib/", "test/support", "bench/"]
  defp elixirc_path(_), do: ["lib/"]

  def application do
    [
      extra_applications: applications(Mix.env()),
      included_applications: [:amoc],
      mod: {LiveLoad.Application, []}
    ]
  end

  defp applications(:dev), do: applications(:all) ++ [:remixed_remix, :runtime_tools]
  defp applications(_all), do: [:logger, :os_mon]

  defp deps do
    [
      # Core Dependencies
      {:flame, "~> 0.5.3"},
      {:amoc, "~> 4.1", runtime: false},
      {:telemetry, "~> 1.0"},
      # TODO: Unfork and retire when required Playwright PRs are merged
      # https://github.com/ftes/playwright_ex/pull/34
      # https://github.com/ftes/playwright_ex/pull/35
      {:live_load_forked_playwright_ex, "0.5.0-fork.2"},
      # {:playwright_ex, "~> 0.5.0"},
      {:ddskerl, "~> 0.4.3"},
      ## Optional Dependencies
      {:jason, "~> 1.4", optional: true},
      {:poison, "~> 6.0", optional: true},
      ## Testing and Development Dependencies
      {:flame_peer, "~> 1.0.0", only: [:dev, :test]},
      {:git_hooks, "~> 0.8.0", only: [:dev], runtime: false},
      {:styler, "~> 1.11", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:remixed_remix, "~> 2.0.2", only: :dev},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.0", only: :dev},
      {:benchee_markdown, "~> 0.3", only: :dev}
    ]
  end

  defp aliases do
    [docs: ["docs", &copy_images/1]]
  end

  defp docs do
    [
      main: "devlog",
      api_reference: false,
      # TODO: A logo?
      # logo: something?
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: extras(),
      extra_section: "GUIDES",
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md"),
        Changes: ["DEVLOG.md", "CHANGELOG.md"]
      ],
      groups_for_modules: groups_for_modules(),
      skip_undefined_reference_warnings_on: Path.wildcard("**/*.md")
    ]
  end

  defp extras do
    [
      "guides/writing_your_first_scenario.md",
      "guides/phoenix_baselines.md",
      "DEVLOG.md": [title: "Devlog"],
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  defp groups_for_modules do
    [
      LiveLoad: [
        LiveLoad,
        LiveLoad.JSON
      ],
      "LiveLoad.Cluster": [
        LiveLoad.Cluster,
        LiveLoad.Cluster.Node
      ],
      "LiveLoad.Result": [
        LiveLoad.Result,
        LiveLoad.Result.Users,
        LiveLoad.Result.ScenarioResult,
        LiveLoad.Result.NodeResult,
        LiveLoad.Result.Bucket,
        LiveLoad.Result.DimensionedHistogram,
        LiveLoad.Result.DimensionedCounter,
        LiveLoad.Result.PrecomputedQuantiles
      ],
      Scenario: [
        LiveLoad.Scenario,
        LiveLoad.Scenario.Context,
        LiveLoad.Scenario.Error
      ],
      Browser: [
        LiveLoad.Browser,
        LiveLoad.Browser.Context
      ],
      "Browser.Connection": [
        LiveLoad.Browser.Connection,
        LiveLoad.Browser.Connection.Playwright
      ]
    ]
  end

  defp copy_images(_) do
    File.mkdir_p!("./doc/assets")

    "./assets/*.{gif,png,jpg,jpeg}"
    |> Path.wildcard()
    |> Enum.each(&File.cp!(&1, Path.join(["doc", "assets", Path.basename(&1)])))
  end
end
