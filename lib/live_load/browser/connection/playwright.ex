defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc false

  use Supervisor
  use LiveLoad.Browser.Connection

  alias __MODULE__
  alias LiveLoad.Browser
  alias LiveLoad.Browser.Connection
  alias LiveLoad.Browser.Context

  @type option() ::
          {:playwright_cli_path, Path.t()}
          | {:name, GenServer.name()}
          | {:playwright_version, Version.version()}
          | {:startup_timeout, pos_integer()}

  @impl Connection
  def new_context(%Browser{} = browser) do
    playwright_browser = browser.private.playwright_connection_browser

    case PlaywrightEx.Browser.new_context(playwright_browser.guid, timeout: 10_000) do
      {:ok, context} -> browser |> Context.new() |> Context.put_private(:playwright_connection_context, context)
      {:error, _reason} = error -> error
    end
  end

  @impl Connection
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
        Playwright.Decompressor.extract!(playwright_version)
      end)

    Supervisor.start_link(__MODULE__, {playwright_cli_path, timeout}, name: name)
  end

  @impl Connection
  def after_start(%Browser{} = browser) do
    {:ok, playwright_browser} = PlaywrightEx.launch_browser(:chromium, timeout: 10_000)
    Browser.put_private(browser, :playwright_connection_browser, playwright_browser)
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
