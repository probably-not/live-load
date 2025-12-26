defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc false

  use Supervisor
  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser.Connection.Playwright.Decompressor

  @type option() ::
          {:playwright_cli_path, Path.t()}
          | {:name, GenServer.name()}
          | {:playwright_version, Version.version()}
          | {:startup_timeout, pos_integer()}

  @impl true
  def new_context(%LiveLoad.Browser{} = browser) do
    playwright_browser = browser.private.playwright_connection_browser
    PlaywrightEx.Browser.new_context(playwright_browser.guid, timeout: 10_000)
  end

  @impl LiveLoad.Browser.Connection
  def start_link(opts) do
    validations = [
      :playwright_cli_path,
      name: __MODULE__,
      playwright_version: playwright_version_from_env(),
      startup_timeout: 1000
    ]

    opts = Keyword.validate!(opts, validations)

    {name, opts} = Keyword.pop!(opts, :name)
    {timeout, opts} = Keyword.pop!(opts, :startup_timeout)
    {playwright_version, opts} = Keyword.pop!(opts, :playwright_version)

    {playwright_cli_path, _opts} =
      Keyword.pop_lazy(opts, :playwright_cli_path, fn ->
        Decompressor.extract!(playwright_version)
      end)

    Supervisor.start_link(__MODULE__, {playwright_cli_path, timeout}, name: name)
  end

  @impl true
  def after_start(%LiveLoad.Browser{} = browser) do
    {:ok, playwright_browser} = PlaywrightEx.launch_browser(:chromium, timeout: 10_000)
    LiveLoad.Browser.put_private(browser, :playwright_connection_browser, playwright_browser)
  end

  @impl Supervisor
  def init({playwright_cli_path, timeout}) do
    children = [
      {PlaywrightEx.Supervisor, [executable: playwright_cli_path, timeout: timeout]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @default_playwright_version "1.57.0"
  defp playwright_version_from_env do
    Application.get_env(:live_load, :playwright_version, @default_playwright_version)
  end
end
