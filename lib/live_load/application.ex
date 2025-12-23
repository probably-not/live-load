defmodule LiveLoad.Application do
  @moduledoc false

  use Application

  @default_playwright_version "1.57.0"

  @impl true
  def start(_type, _args) do
    playwright_version = Application.get_env(:live_load, :playwright_version, @default_playwright_version)
    playwright_cli = LiveLoad.Browser.Playwright.Decompressor.extract!(playwright_version)

    children = [
      {PlaywrightEx.Supervisor, [executable: playwright_cli, timeout: 1000]}
    ]

    opts = [strategy: :one_for_one, name: LiveLoad.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
