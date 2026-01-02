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

      Module.register_attribute(__MODULE__, :required_variable, persist: true, accumulate: true)

      @required_variable %{
        name: :runner_pid,
        default_value: nil,
        description: ~c"INTERNAL VARIABLE. The PID of the process running the load test"
      }

      @required_variable %{
        name: :heartbeat_timeout_seconds,
        default_value: 10,
        description: ~c"""
        INTERNAL VARIABLE.
        How long to wait (in seconds) between heartbeats to determine if the scenario has completed.
        A scenario must send a heartbeat at least once per timeout to ensure that it does not die prematurely.
        The timeout defaults to 10 seconds.
        """
      }

      scenario_timeout =
        cond do
          is_nil(opts[:timeout]) ->
            to_timeout(minute: 10)

          not is_integer(opts[:timeout]) ->
            message = """
            timeout option #{inspect(opts[:timeout])} passed in to the LiveLoad.Scenario is not a valid timeout \
            (in module #{inspect(__MODULE__)}).

            We will override it with a default timeout of 10 minutes for now.
            """

            IO.warn(message, __ENV__)
            to_timeout(minute: 10)

          true ->
            opts[:timeout]
        end

      @required_variable %{
        name: :scenario_timeout,
        default_value: scenario_timeout,
        description: ~c"""
        INTERNAL VARIABLE.
        The maximum time for a scenario to take.
        If a scenario takes longer than this, a timeout error will be returned.
        The default value is #{scenario_timeout}
        """
      }

      @impl :amoc_scenario
      def init do
        LiveLoad.Scenario.Init.init(__MODULE__)
      end

      @impl :amoc_scenario
      def start(user_id, opts) do
        LiveLoad.Scenario.Runner.run(__MODULE__, user_id, opts)
      end

      def config, do: {:ok, %{}}
      defoverridable config: 0
    end
  end
end
