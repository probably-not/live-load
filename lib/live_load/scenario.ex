defmodule LiveLoad.Scenario do
  @moduledoc false

  @type t() :: module()
  @type config() :: map()
  @type user_id() :: integer() | binary()
  @type user_result() :: :ok | {:ok, term()} | {:error, term()} | term()

  @callback config() :: {:ok, config()} | {:error, term()}
  @callback run(user_id :: user_id(), config :: config()) :: user_result()

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour :amoc_scenario
      @behaviour LiveLoad.Scenario

      Module.register_attribute(__MODULE__, :required_variable, persist: true)

      @required_variable [
        %{name: :runner_pid, default_value: nil, description: ~c"The PID of the process running the load test"},
        %{
          name: :heartbeat_timeout_seconds,
          default_value: 10,
          description: ~c"""
          How long to wait (in seconds) between heartbeats to determine if the scenario has completed.
          A scenario must send a heartbeat at least once per timeout to ensure that it does not die prematurely.
          The timeout defaults to 10 seconds.
          """
        }
      ]

      @impl :amoc_scenario
      def init do
        runner_pid = :amoc_config.get(:runner_pid)
        heartbeat_timeout = :amoc_config.get(:heartbeat_timeout_seconds)

        plan = [
          {:all,
           fn {:timeout, _count} ->
             send(runner_pid, {:scenario_timeout, __MODULE__, node()})
           end}
        ]

        # We manually increase the coordinator timeout by a few seconds.
        # The heartbeat will run on the heartbeat timeout, and will die off
        # when the running process completes.
        coordinator_timeout = heartbeat_timeout + 3
        :amoc_coordinator.start({__MODULE__, :heartbeat}, plan, coordinator_timeout)

        {:ok,
         %{
           scenario_config: config(),
           __config__: %{
             runner_pid: runner_pid,
             heartbeat_timeout: to_timeout(second: heartbeat_timeout)
           }
         }}
      end

      @impl :amoc_scenario
      def start(user_id, opts) do
        LiveLoad.Scenario.Runner.run(__MODULE__, user_id, opts)
      end

      def config, do: %{}
      defoverridable config: 0
    end
  end
end
