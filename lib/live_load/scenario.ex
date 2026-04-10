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

  ## Scenario Lifecycle

  When a `LiveLoad.Scenario` is run, the `c:config/1` callback is called once per node, before any
  user processes are created. The value returned from `c:config/1` is then passed into the `c:run/3`
  callback on every iteration of the scenario for every user.

  After `c:config/1` returns, `LiveLoad` creates the configured number of user processes for this node.
  Each user process is given its own `LiveLoad.Browser.Context` and `LiveLoad.Scenario.Context`, and
  the user process enters a loop that calls the scenario's `c:run/3` callback over and over until
  the configured `:scenario_duration` has been reached.

  Each iteration of the loop runs `c:run/3` with the current `LiveLoad.Scenario.Context` and the config
  that was returned from `c:config/1`. The `LiveLoad.Scenario.Context` returned from `c:run/3` becomes
  the context for the next iteration, allowing values to be carried forward via `LiveLoad.Scenario.Context.assign/3`.
  See `LiveLoad.Scenario.Context` for more details on how the context is maintained across iterations.

  If `c:run/3` returns a context that is `halted?` or `failed?`, or if it raises an exception, the
  user process will be terminated and no further iterations will run for that user. Any other users
  on the node will continue running their own iterations until the `:scenario_duration` is reached.

  Once the `:scenario_duration` has elapsed, the user processes will finish their current iteration
  and then terminate. The scenario is considered complete once all user processes on all nodes have
  terminated.
  """

  alias __MODULE__

  @typedoc "Any module implementing the `LiveLoad.Scenario` behaviour."
  @type t() :: module()

  @typedoc """
  A config that is created by the `c:config/1` callback on initialization of the `LiveLoad.Scenario`.

  A config can be any term, as it will simply be passed into the `c:run/3` callback and can be handled by the scenario.
  """
  @type config() :: map() | keyword() | struct() | term()

  @typedoc false
  @type internal_config() :: %{
          local_listener_pid: pid(),
          browser: LiveLoad.Browser.t(),
          iteration_timeout: timeout(),
          scenario_duration: timeout()
        }

  @typedoc "The user ID passed to the `c:run/3` callback. It can be either an integer or a binary."
  @type user_id() :: integer() | binary()

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
  @callback run(context :: Scenario.Context.t(), user_id :: user_id(), config :: config()) ::
              Scenario.Context.t() | {:error, term()}

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour :amoc_scenario
      @behaviour LiveLoad.Scenario

      import LiveLoad.Scenario.Context,
        only: [
          assign: 3,
          reset_assigns: 1,
          clear_assign: 2,
          update_assign!: 3,
          halt: 1,
          halted?: 1,
          failed?: 1,
          navigate: 2,
          reload: 1,
          wait_for_selector: 2,
          click: 2,
          fill: 3,
          press: 3,
          clear: 2,
          check: 2,
          uncheck: 2,
          select_option: 3,
          select_multiple_options: 3,
          focus: 2,
          blur: 2,
          hover: 2,
          drag_and_drop: 3,
          ensure_liveview: 1,
          wait_for_liveview: 1,
          wait_for_phx_loading_completion: 3,
          submit_form: 2,
          page_content: 1,
          page_content: 2,
          inner_html: 2,
          inner_html: 3,
          inner_text: 2,
          inner_text: 3,
          text_content: 2,
          text_content: 3,
          input_value: 2,
          input_value: 3,
          get_attribute: 3,
          get_attribute: 4,
          visible?: 2,
          visible?: 3,
          checked?: 2,
          checked?: 3
        ]

      Module.register_attribute(__MODULE__, :required_variable, persist: true, accumulate: true)

      @required_variable %{
        name: :collector_pid,
        default_value: nil,
        description: "INTERNAL VARIABLE. The PID of the telemetry collector process on the runner node"
      }

      @required_variable %{
        name: :browser_connection_adapter,
        default_value: nil,
        description: """
        INTERNAL VARIABLE.
        The `LiveLoad.Browser.Connection` adapter that will be used for this load test.
        """
      }

      @required_variable %{
        name: :browser_connection_opts,
        default_value: [],
        description: """
        INTERNAL VARIABLE.
        The `t:LiveLoad.Browser.Connection.opts()` that will be passed
        to the browser initialization during this load test.
        """
      }

      @required_variable %{
        name: :iteration_timeout,
        default_value: nil,
        description: """
        INTERNAL VARIABLE.
        The maximum time for single iteration of a scenario to take.
        If an iteration of a scenario takes longer than this, a timeout error will be returned.
        """
      }

      @required_variable %{
        name: :scenario_duration,
        default_value: nil,
        description: """
        INTERNAL VARIABLE.
        The maximum time for a load test to be running a single scenario.
        At the end of this timeout, the scenario runner will transition to a terminating state
        and wait for the last iteration to complete, then report its completion.
        """
      }

      @required_variable %{
        name: :scenario_config_opts,
        default_value: [],
        description: """
        INTERNAL VARIABLE.
        The config opts keyword list that is passed to the scenario's config/1 callback.
        """
      }

      @impl :amoc_scenario
      @doc false
      def init do
        Scenario.Callbacks.init(__MODULE__)
      end

      @impl :amoc_scenario
      @doc false
      def start(user_id, opts) do
        Scenario.Callbacks.start(__MODULE__, user_id, opts)
      end

      @impl :amoc_scenario
      @doc false
      def terminate(opts) do
        Scenario.Callbacks.terminate(__MODULE__, opts)
      end

      @impl LiveLoad.Scenario
      @doc false
      def config(_opts), do: {:ok, %{}}
      defoverridable config: 1
    end
  end
end
