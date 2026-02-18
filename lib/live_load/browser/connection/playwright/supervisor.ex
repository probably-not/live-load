defmodule LiveLoad.Browser.Connection.Playwright.Supervisor do
  @moduledoc false
  use Supervisor

  alias LiveLoad.Browser.Connection.Playwright.Decompressor

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
  def init({playwright_cli_path, timeout}) do
    children = [
      {PlaywrightEx.Supervisor,
       [
         name: __MODULE__.Playwright,
         executable: playwright_cli_path,
         timeout: timeout,
         js_logger: LiveLoad.Browser.Connection.Playwright.JsLogger
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def playwright_connection_name do
    PlaywrightEx.Supervisor.connection_name(__MODULE__.Playwright)
  end

  @default_playwright_version "1.57.0"
  defp playwright_version_from_env do
    Application.get_env(:live_load, :playwright_version, @default_playwright_version)
  end
end
