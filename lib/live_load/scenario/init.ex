defmodule LiveLoad.Scenario.Init do
  @moduledoc false

  def init(scenario) do
    runner_pid = :amoc_config.get(:runner_pid)
    heartbeat_timeout = :amoc_config.get(:heartbeat_timeout_seconds)

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
       scenario_config: scenario.config(),
       __config__: %{
         runner_pid: runner_pid,
         heartbeat_timeout: to_timeout(second: heartbeat_timeout)
       }
     }}
  end
end
