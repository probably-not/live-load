defmodule LiveLoad.Scenario.Callbacks do
  @moduledoc false

  alias LiveLoad.Browser
  alias LiveLoad.Scenario
  alias LiveLoad.Telemetry

  def init(scenario) do
    collector_pid = :amoc_config.get(:collector_pid)
    iteration_timeout = :amoc_config.get(:iteration_timeout)
    scenario_duration = :amoc_config.get(:scenario_duration)
    browser_connection_adapter = :amoc_config.get(:browser_connection_adapter)
    browser_connection_opts = :amoc_config.get(:browser_connection_opts)
    opts = :amoc_config.get(:scenario_config_opts)

    with {:ok, scenario_config} <- scenario.config(opts),
         {:ok, %Browser{} = browser} <-
           Browser.start_link(browser_connection_adapter, browser_connection_opts),
         {:ok, listener_pid} <- Telemetry.Listener.start_link({collector_pid, browser}) do
      {:ok,
       %{
         scenario_config: scenario_config,
         __config__: %{
           local_listener_pid: listener_pid,
           browser: browser,
           iteration_timeout: iteration_timeout,
           scenario_duration: scenario_duration
         }
       }}
    end
  end

  def start(scenario, user_id, opts) do
    case Browser.new_context(opts.__config__.browser) do
      {:ok, %Browser.Context{} = browser_context} ->
        try do
          Scenario.Runner.run(scenario, Scenario.Context.new(browser_context), user_id, opts)
        after
          Browser.Context.stop(browser_context)
        end

      {:error, reason} ->
        raise RuntimeError, """
        Failed to initialize the browser context for #{inspect(scenario)} with reason: #{inspect(reason)}
        """
    end
  end

  def terminate(_scenario, opts) do
    Browser.stop(opts.__config__.browser)
    Telemetry.Listener.stop(opts.__config__.local_listener_pid)
  end
end
