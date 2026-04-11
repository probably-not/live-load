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

    case System.cmd(playwright_cli_path, ["install-deps chromium"]) do
      {_, 0} ->
        :ok

      {output, code} ->
        raise """
        Failed to install dependencies of the chromium browser during decompression (code: #{code}).

        Command output:

        #{output}
        """
    end

    Supervisor.start_link(__MODULE__, {playwright_cli_path, browsers_path(playwright_version), timeout}, name: name)
  end

  @impl true
  def init({playwright_cli_path, browsers_path, timeout}) do
    children = [
      {PlaywrightEx.Supervisor,
       [
         name: __MODULE__.Playwright,
         executable: playwright_cli_path,
         env: %{"PLAYWRIGHT_BROWSERS_PATH" => browsers_path},
         timeout: timeout,
         js_logger: LiveLoad.Browser.Connection.Playwright.JsLogger
       ]},
      Supervisor.child_spec(
        {LiveLoad.Browser.Connection.Playwright.Metrics, playwright_connection_name()},
        id: :metrics
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics_pid!(supervisor) do
    case LiveLoad.SupUtils.find_child(supervisor, :metrics) do
      metrics when is_pid(metrics) ->
        metrics

      nil ->
        raise RuntimeError, """
        The metrics `LiveLoad.Browser.Connection.Playwright.Metrics` could not be found under the given supervisor!

        This should never happen, as the `LiveLoad.Browser.Connection.Playwright.Supervisor.metrics_pid!/1` function
        should only ever be called on a `LiveLoad.Browser.Connection.Playwright.Supervisor` that is successfully running
        which must contain a `LiveLoad.Browser.Connection.Playwright.Metrics` process running underneath it.

        If you've reached this exception and you are certain that the PID that was passed in to the function is a properly
        created `LiveLoad.Browser.Connection.Playwright.Supervisor`, that means something is critically wrong in `LiveLoad`
        itself and this should be reported to the maintainers.

        Please file issues at: https://github.com/probably-not/live-load/issues.
        """
    end
  end

  def playwright_connection_name do
    PlaywrightEx.Supervisor.connection_name(__MODULE__.Playwright)
  end

  @default_playwright_version "1.59.1"
  def playwright_version_from_env do
    Application.get_env(:live_load, :playwright_version, @default_playwright_version)
  end

  defp browsers_path(version) do
    Application.app_dir(:live_load, ["priv", "playwright", version, "bin", "browsers"])
  end
end
