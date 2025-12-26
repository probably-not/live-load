defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc false

  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser
  alias LiveLoad.Browser.Context

  @type option() ::
          {:playwright_cli_path, Path.t()}
          | {:name, GenServer.name()}
          | {:playwright_version, Version.version()}
          | {:startup_timeout, pos_integer()}

  @impl true
  defdelegate start_link(opts), to: LiveLoad.Browser.Connection.Playwright.Supervisor

  @impl true
  def new_context(%Browser{} = browser) do
    playwright_browser = browser.private.playwright_connection_browser

    case PlaywrightEx.Browser.new_context(playwright_browser.guid, timeout: 10_000) do
      {:ok, context} -> browser |> Context.new() |> Context.put_private(:playwright_connection_context, context)
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def after_start(%Browser{} = browser) do
    {:ok, playwright_browser} = PlaywrightEx.launch_browser(:chromium, timeout: 10_000)
    Browser.put_private(browser, :playwright_connection_browser, playwright_browser)
  end
end
