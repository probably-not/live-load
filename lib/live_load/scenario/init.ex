defmodule LiveLoad.Scenario.Init do
  @moduledoc false

  def init(scenario) do
    collector_pid = :amoc_config.get(:collector_pid)
    iteration_timeout = :amoc_config.get(:iteration_timeout)
    scenario_duration = :amoc_config.get(:scenario_duration)
    browser_connection_adapter = :amoc_config.get(:browser_connection_adapter)
    browser_connection_opts = :amoc_config.get(:browser_connection_opts)
    opts = :amoc_config.get(:scenario_config_opts)

    with {:ok, scenario_config} <- scenario.config(opts),
         {:ok, %LiveLoad.Browser{} = browser} <-
           LiveLoad.Browser.start_link(browser_connection_adapter, browser_connection_opts),
         {:ok, listener_pid} <- LiveLoad.Telemetry.Listener.start_link({collector_pid, browser}) do
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
end
