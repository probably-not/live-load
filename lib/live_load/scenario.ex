defmodule LiveLoad.Scenario do
  @moduledoc """
  A behaviour module for implementing a load testing scenario to be run via LiveLoad.

  A `LiveLoad.Scenario` runs in a distributed fashion. Nodes are elastically created
  via LiveLoad whenever a load test is being performed. On each node, the `c:config/1`
  callback is called once, to initialize the node's configuration, and a set of user
  processes are created and run to simulate the load by calling the scenario's `c:run/3`
  callback with the current user ID and the config that was created for this node.

  > ### `use LiveLoad.Scenario` {: .warning}
  >
  > In order for LiveLoad to be able to run your scenario correctly,
  > you must `use LiveLoad.Scenario`. This will not only set the behaviour
  > for LiveLoad, but also set up various functionality related to running
  > the scenario properly through LiveLoad's internals. LiveLoad's internals
  > are opaque, and while you can see how they work by browsing the code and
  > reading the docs, they should not be assumed to be stable. Ensuring that
  > you are creating scenarios with `use LiveLoad.Scenario` will make certain
  > that any scenario you create will be stable and runnable by LiveLoad.

  > ### The `c:config/1` callback {: .info}
  >
  > When you `use LiveLoad.Scenario`, the `LiveLoad.Scenario` module will
  > define an empty `c:config/1` function for you which will return an empty map.
  > If you don't need any configurable parts in your scenario, this injected
  > callback can remain and does not need to be overriden by your scenario module.
  """

  alias __MODULE__
  alias LiveLoad.Browser

  @typedoc "Any module implementing the `LiveLoad.Scenario` behaviour."
  @type t() :: module()

  @typedoc """
  A config that is created by the `c:config/1` callback on initialization of the `LiveLoad.Scenario`.

  A config can be any term, as it will simply be passed into the `c:run/3` callback and can be handled by the scenario.
  """
  @type config() :: map() | keyword() | struct() | term()

  @typedoc false
  @type internal_config() :: %{runner_pid: pid(), heartbeat_timeout: timeout(), scenario_timeout: timeout()}

  @typedoc "The user ID passed to the `c:run/3` callback. It can be either an integer or a binary."
  @type user_id() :: integer() | binary()

  @typedoc """
  The result that is returned by the `c:run/3` callback.

  Result values are discarded and ignored by LiveLoad, as they have no bearing
  on the results of the load test. However, whether or not the result was successful
  is tracked. Successful results are qualified as `:ok` or `{:ok, ignored}`. Any other
  value that is returned by the `c:run/3` callback will be qualified as an error and
  marked as failed in the results of the load test.
  """
  @type user_result() :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Invoked once per node that LiveLoad is running the load test on.
  `c:config/1` will receive any options passed in to `LiveLoad.run/1`
  that have not been consumed yet and can return a config value that
  will be passed in to `c:run/3`.

  `c:config/1` is called synchronously on startup, and if an error is
  returned, the entire load test will fail for this scenario.
  """
  @callback config(opts :: keyword()) :: {:ok, config()} | {:error, term()}

  @doc """
  Invoked once per user. `c:run/3` is the actual load test that will be run,
  measured, and instrumented by LiveLoad.
  """
  @callback run(context :: LiveLoad.Scenario.Context.t(), user_id :: user_id(), config :: config()) :: user_result()

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour :amoc_scenario
      @behaviour LiveLoad.Scenario

      import LiveLoad.Scenario.Context,
        only: [
          assign: 3,
          clear_assign: 2,
          update_assign!: 3,
          halt: 1,
          halted?: 1,
          failed?: 1,
          navigate: 2,
          wait_for_selector: 2,
          ensure_liveview: 1,
          wait_for_liveview: 1
        ]

      Module.register_attribute(__MODULE__, :required_variable, persist: true, accumulate: true)

      @required_variable %{
        name: :runner_pid,
        default_value: nil,
        description: ~c"INTERNAL VARIABLE. The PID of the process running the load test"
      }

      @required_variable %{
        name: :browser_connection_adapter,
        default_value: nil,
        description: ~c"""
        INTERNAL VARIABLE.
        The `LiveLoad.Browser.Connection` adapter that will be used for this load test.
        """
      }

      @required_variable %{
        name: :browser_connection_opts,
        default_value: [],
        description: ~c"""
        INTERNAL VARIABLE.
        The `t:LiveLoad.Browser.Connection.opts()` that will be passed
        to the browser initialization during this load test.
        """
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

      @required_variable %{
        name: :scenario_config_opts,
        default_value: [],
        description: ~c"""
        INTERNAL VARIABLE.
        The config opts keyword list that is passed to the scenario's config/1 callback.
        """
      }

      @impl :amoc_scenario
      @doc false
      def init do
        Scenario.Init.init(__MODULE__)
      end

      @impl :amoc_scenario
      @doc false
      def start(user_id, opts) do
        case Browser.new_context(opts.__config__.browser) do
          {:ok, %Browser.Context{} = browser_context} ->
            try do
              Scenario.Runner.run(__MODULE__, Scenario.Context.new(browser_context), user_id, opts)
            after
              Browser.Context.stop(browser_context)
            end

          {:error, _reason} = error ->
            error
        end
      end

      @impl :amoc_scenario
      @doc false
      def terminate(opts) do
        Browser.stop(opts.__config__.browser)
      end

      @impl LiveLoad.Scenario
      @doc false
      def config(_opts), do: {:ok, %{}}
      defoverridable config: 1
    end
  end
end
