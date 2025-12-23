defmodule Mix.Tasks.InitPlaywright do
  @shortdoc "Installs the Playwright packages necessary to set up Playwright locally"

  @moduledoc false
  use Mix.Task

  def run([version]) do
    assets_dir = "assets"
    File.mkdir_p!(assets_dir)
    System.cmd("npm", ["install", "playwright@#{version}"], cd: assets_dir)

    priv_dir = "priv/playwright"
    File.mkdir_p!(priv_dir)

    playwright_source = Path.join([assets_dir, "node_modules", "playwright"])
    playwright_core_source = Path.join([assets_dir, "node_modules", "playwright-core"])

    archive_path = Path.join([priv_dir, version, "playwright_bundle.tar.gz"])

    :erl_tar.create(
      String.to_charlist(archive_path),
      [String.to_charlist(playwright_core_source), String.to_charlist(playwright_source)],
      [:compressed]
    )

    Mix.shell().info("Compressed playwright to #{archive_path}")
  end
end
