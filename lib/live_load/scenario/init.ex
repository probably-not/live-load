defmodule LiveLoad.Scenario.Init do
  @moduledoc false

  def init(scenario) do
    collector_pid = :amoc_config.get(:collector_pid)
    scenario_timeout = :amoc_config.get(:scenario_timeout)
    browser_connection_adapter = :amoc_config.get(:browser_connection_adapter)
    browser_connection_opts = :amoc_config.get(:browser_connection_opts)
    opts = :amoc_config.get(:scenario_config_opts)

    with {:ok, listener_pid} <- LiveLoad.Telemetry.Listener.start_link(collector_pid),
         {:ok, scenario_config} <- scenario.config(opts),
         {:ok, %LiveLoad.Browser{} = browser} <-
           LiveLoad.Browser.start_link(browser_connection_adapter, browser_connection_opts) do
      {:ok,
       %{
         scenario_config: scenario_config,
         __config__: %{
           local_listener_pid: listener_pid,
           browser: browser,
           scenario_timeout: scenario_timeout
         }
       }}
    end
  end
end
