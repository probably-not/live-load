defmodule LiveLoad.Scenario.Init do
  @moduledoc false

  def init(scenario) do
    runner_pid = :amoc_config.get(:runner_pid)
    heartbeat_timeout = :amoc_config.get(:heartbeat_timeout_seconds)
    scenario_timeout = :amoc_config.get(:scenario_timeout)
    browser_connection_adapter = :amoc_config.get(:browser_connection_adapter)
    browser_connection_opts = :amoc_config.get(:browser_connection_opts)
    opts = :amoc_config.get(:scenario_config_opts)

    with {:ok, scenario_config} <- scenario.config(opts),
         {:ok, %LiveLoad.Browser{} = browser} <-
           LiveLoad.Browser.start_link(browser_connection_adapter, browser_connection_opts) do
      plan = [
        {:all,
         fn {:timeout, _count} ->
           send(runner_pid, {:scenario_timeout, scenario, node()})
         end}
      ]

      # We manually increase the coordinator timeout by a few seconds.
      # The heartbeat will run on the heartbeat timeout, and will die off
      # when the running process completes.
      coordinator_timeout = heartbeat_timeout + 3
      :amoc_coordinator.start({scenario, :heartbeat}, plan, coordinator_timeout)

      {:ok,
       %{
         scenario_config: scenario_config,
         __config__: %{
           runner_pid: runner_pid,
           browser: browser,
           heartbeat_timeout: to_timeout(second: heartbeat_timeout),
           scenario_timeout: scenario_timeout
         }
       }}
    end
  end
end
