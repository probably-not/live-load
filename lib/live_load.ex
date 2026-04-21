defmodule LiveLoad do
  @moduledoc """
  A load testing framework for simulating real, distributed, live load on your application.

  `LiveLoad` uses real browser automation to simulate actual user interactions with your Phoenix LiveView application.
  Each simulated user is a real browser context: it navigates, clicks, fills forms, and waits for LiveView
  events to complete, exactly the way a real user would. LiveLoad collects LiveView-aware metrics from both sides:
  HTTP and WebSocket telemetry from the browser, plus instrumentation for things like `phx-*-loading` DOM patching
  and connection lifecycle events.

  ## Quick Start

  ```elixir
  defmodule MyApp.LoadTest.BrowseScenario do
    use LiveLoad.Scenario

    @impl true
    def run(context, _user_id, _config) do
      context
      |> navigate("https://myapp.com/")
      |> wait_for_liveview()
      |> click("#some-button")
      |> wait_for_phx_loading_completion(:click, "#some-button")
    end
  end
  ```

  Then run it:

  ```elixir
  results = LiveLoad.run(
    scenario: MyApp.LoadTest.BrowseScenario,
    users: 25,
    scenario_duration: to_timeout(minute: 5)
  )
  ```

  For distributed runs across multiple nodes via `FLAME`:

  ```elixir
  results = LiveLoad.run(
    scenario: MyApp.LoadTest.BrowseScenario,
    users: 1_000,
    distributed?: true,
    flame_backend: FLAME.FlyBackend,
    cluster_opts: [
      flame_backend_opts: [app: :my_runner_app, cpus: 8, memory_mb: 16 * 1024],
      max_allowed_nodes: 100
    ]
  )
  ```

  ## Reporting

  The `LiveLoad.Result` struct returned for each scenario is fully JSON-serializable and contains
  histograms, time-series data, dimensional breakdowns, and per-node results. You can write it to a file,
  pipe it into your own analysis, or use one of the built-in reporters:

  ```elixir
  # Generate a self-contained HTML report
  html = LiveLoad.Reporter.HTML.render!(results)
  File.write!("liveload_report.html", html)
  ```

  For a more complete walkthrough of everything you can do inside a `LiveLoad.Scenario`,
  from basic navigation to throttles and assigns, head to the
  [Writing Your First Scenario guide](guides/writing_your_first_scenario.md).
  """

  alias LiveLoad.Browser
  alias LiveLoad.Cluster
  alias LiveLoad.Scenario
  alias LiveLoad.Scenario.Discovery

  @typedoc """
  Defines the OTP application to load test.

  This option is used in order to automatically discover `LiveLoad.Scenario` modules implemented in the given application.
  Similarly to Ecto Migrations, `LiveLoad` will scan the given OTP application, find all `LiveLoad.Scenario` modules, and then
  run these scenarios for a load test.

  This option is required unless a `t:scenario_opt/0` or a `t:scenarios_opt/0` is given,
  in which case only the given scenario modules will be run.

  This option takes the lowest priority.
  """
  @type otp_app_opt() :: {:otp_app, atom()}

  @typedoc """
  Run a single scenario module.

  This option is mutually exclusive with `t:scenarios_opt/0` and `t:otp_app_opt/0`, each of which configure which scenarios should be run.

  This option takes the highest priority.
  """
  @type scenario_opt() :: {:scenario, Scenario.t()}

  @typedoc """
  Run a list of scenario modules.

  This option is mutually exclusive with `t:scenario_opt/0` and `t:otp_app_opt/0`, each of which configure which scenarios should be run.

  This option takes the second highest priority.
  """
  @type scenarios_opt() :: {:scenarios, [Scenario.t()]}

  @typedoc """
  Configures the run to be distributed.

  When set to `true`, `LiveLoad` will use `FLAME` to build an ad-hoc pool of nodes based on the given `FLAME.Pool` configuration
  and evenly distribute the users across these nodes during the run.

  Defaults to `false`.
  """
  @type distributed_run_opt() :: {:distributed?, boolean()}

  @typedoc """
  Configures the number of user processes to use for the run.

  Defaults to a single user.
  """
  @type users_count_opt() :: {:users, pos_integer()}

  @typedoc """
  Defines the `LiveLoad.Browser.Connection` implementation to use for this run.

  Defaults to `LiveLoad.Browser.Connection.Playwright`.
  """
  @type browser_connection_adapter_opt() :: {:browser_connection_adapter, Browser.Connection.t()}

  @typedoc """
  Options passed to the given `t:browser_connection_adapter_opt/0` on initialization of the `LiveLoad.Browser.Connection`.

  Defaults to an empty list.
  """
  @type browser_connection_opts_opt() :: {:browser_connection_opts, Browser.Connection.opts()}

  @typedoc """
  Defines the timeout for a single iteration of a scenario.

  If this timeout is reached and the scenario has not completed, it will be killed and the user's status will reported as a failure.
  No other iterations will take place for that user.

  Defaults to 2 minutes.

  _Note: while the type here is set to `t:timeout/0`, the `:infinity` value is invalid and an error will be returned if it is passed._
  """
  @type scenario_iteration_timeout_opt() :: {:iteration_timeout, timeout()}

  @typedoc """
  Defines the duration of the entire load test for a specific scenario.

  When running a load test, the scenario's `c:LiveLoad.Scenario.run/3` callback will be run in a loop multiple times
  until this value is reached. Once reached, the runner will transition to a terminating state and wait for the latest
  iteration of the scenario to complete, and then report its completion.

  Defaults to 10 minutes.

  _Note: while the type here is set to `t:timeout/0`, the `:infinity` value is invalid and an error will be returned if it is passed._
  """
  @type scenario_duration_opt() :: {:scenario_duration, timeout()}

  @typedoc """
  Defines the `FLAME.Backend` module to use when running a distributed load test.

  The `LiveLoad.Cluster` can be additionally configured by passing the `t:cluster_opts_opt/0` option
  to `LiveLoad.run/1`. See `LiveLoad.Cluster` for more details.

  This option is required when running a distributed load test and setting the `t:distributed_run_opt/0` option to `true`.
  """
  @type flame_backend_opt() :: {:flame_backend, Cluster.flame_backend()}

  @typedoc """
  Options passed in to the `LiveLoad.Cluster` initialization.

  This is a list of `t:LiveLoad.Cluster.option/0` that is passed directly into the initialization.

  See `LiveLoad.Cluster` for all available options.
  """
  @type cluster_opts_opt() :: {:cluster_opts, [Cluster.option()]}

  @typedoc """
  Initialization options for running a `LiveLoad.Scenario`.

  These are split between options for the overall run configuration (`t:distributed_run_opt/0`, `t:users_count_opt/0`,
  `t:flame_backend_opt/0`, `t:cluster_opts_opt/0`), options for the runner itself (`t:browser_connection_adapter_opt/0`,
  `t:scenario_iteration_timeout_opt/0`, `t:scenario_duration_opt/0`) and any other options that should be passed in as
  configuration to the scenario `c:LiveLoad.Scenario.config/1` callback.
  """
  @type option() ::
          scenario_opt()
          | scenarios_opt()
          | otp_app_opt()
          | distributed_run_opt()
          | users_count_opt()
          | browser_connection_adapter_opt()
          | scenario_iteration_timeout_opt()
          | scenario_duration_opt()
          | flame_backend_opt()
          | cluster_opts_opt()
          | {atom(), term()}

  @typedoc """
  An error returned by a scenario when the cluster creation process fails to connect to the nodes specified in the cluster.

  The error contains the list of nodes that failed to connect.
  """
  @type failed_to_connect_cluster_error() :: {:error, {:failed_to_connect, failed :: [term()]}}

  @typedoc """
  An error returned by a scenario when the cluster creation process fails to connect within the 30 second timeout
  for connecting to all of the nodes in the specified cluster.

  The error contains the current status of the cluster with details of what nodes are still waiting to connect,
  what nodes failed, and what nodes succeeded.
  """
  @type cluster_connection_timeout_error() :: {:error, {:waiting_for_cluster, %{optional(atom()) => any()}}}

  @typedoc """
  The result of a `LiveLoad.Scenario` run returned by `LiveLoad.run/1`.

  This may either be a `LiveLoad.Result` or an error. If the given `t:distributed_run_opt/0`
  is set to `true`, the error may include one of the possible `t:Cluster.cluster_initialization_error/0` errors.
  """
  @type scenario_result() ::
          LiveLoad.Result.t()
          | Cluster.cluster_initialization_error()
          | failed_to_connect_cluster_error()
          | cluster_connection_timeout_error()
          | {:error, term()}

  @doc """
  Runs all discovered `LiveLoad.Scenario` modules and returns a map of results for each scenario run.

  `run/1` is the main entrypoint for LiveLoad. It accepts a list of `t:option/0` values to configure
  the load test, discovers which scenarios to run, runs each one to completion, and returns a map
  of `t:LiveLoad.Scenario.t/0` keys to `t:scenario_result/0` values.

  Scenarios are run:
  - **Independently**: Each `LiveLoad.Scenario` will create it's own `LiveLoad.Browser`, `LiveLoad.Cluster`,
  and independent user processes
  - **Sequentially**: All scenarios are assumed to be running against the same target, so to ensure that
  the runs are clean, each `LiveLoad.Scenario` is run sequentially in the order that they are discovered.

  `run/1` is synchronous and will block until all discovered scenarios have finished.

  Errors encountered during a scenario are captured in the result map against the scenario that
  produced them and do not prevent other scenarios from running.

  ## Scenario Discovery

  Which scenarios are run is determined by the options given. The following options are mutually
  exclusive, and take priority in the order listed:

  1. `t:scenario_opt/0`: a single `LiveLoad.Scenario` module.
  2. `t:scenarios_opt/0`: a list of `LiveLoad.Scenario` modules.
  3. `t:otp_app_opt/0`: an OTP application atom. LiveLoad will scan the given application for all
     modules implementing the `LiveLoad.Scenario` behaviour and run each of them.

  ## Scenario Configuration

  Any additional options passed to `run/1` that are not consumed as part of the run configuration (such as
  `t:distributed_run_opt/0`, `t:users_count_opt/0`, `t:flame_backend_opt/0`, `t:cluster_opts_opt/0`)
  or runner options (such as `t:browser_connection_adapter_opt/0`, `t:scenario_iteration_timeout_opt/0`, and `t:scenario_duration_opt/0`)
  are forwarded to each scenario's `c:LiveLoad.Scenario.config/1` callback as the `opts` argument. This allows you to pass arbitrary,
  scenario-specific configuration to each `LiveLoad.Scenario` run during the load test.

  ## Examples

  Run all scenarios discovered in `:my_app` with 50 concurrent users for 5 minutes:

  ```elixir
  LiveLoad.run(
    otp_app: :my_app,
    users: 50,
    scenario_duration: to_timeout(minute: 5)
  )
  ```

  Run a specific scenario with 25 concurrent users for 2 minutes:

  ```elixir
  LiveLoad.run(
    scenario: MyApp.LoadTest.CheckoutScenario,
    users: 25,
    scenario_duration: to_timeout(minute: 2)
  )
  ```

  Run a list of specific scenarios with 100 concurrent users for 15 minutes:

  ```elixir
  LiveLoad.run(
    scenarios: [MyApp.LoadTest.CheckoutScenario, MyApp.LoadTest.DeliveryStatusScenario],
    users: 100,
    scenario_duration: to_timeout(minute: 15)
  )
  ```

  Pass custom configuration to allow configuring a scenario's options
  via the `c:LiveLoad.Scenario.config/1` callback:

  ```elixir
  LiveLoad.run(
    scenario: MyApp.LoadTest.CheckoutScenario,
    users: 10,
    base_url: "https://staging.myapp.com",
  )
  ```

  Run a distributed load test across a `FLAME`-provisioned cluster using the `FLAME.FlyBackend`
  using Fly machines with 8 CPUs and 16 GB of RAM, with a maximum of 100 nodes allowed:

  ```elixir
  LiveLoad.run(
    otp_app: :my_app,
    users: 10_000,
    distributed?: true,
    flame_backend: FLAME.FlyBackend,
    cluster_opts: [
      flame_backend_opts: [app: :live_load, cpus: 8, memory_mb: 16 * 1024],
      max_allowed_nodes: 100
    ]
  )
  ```

  ## Consuming Results

  `run/1` returns a map of `t:LiveLoad.Scenario.t/0` keys to `t:scenario_result/0` values. If the `LiveLoad.Scenario`
  completed successfully, the result with be a `LiveLoad.Result` value. `LiveLoad.Result` is a JSON serializable
  struct that contains all information necessary for a deep analysis of what occurred during the load test,
  including histograms, timelines, and stats broken down by various dimensions. The consumer of the result can write
  this data anywhere, and run independent analysis on it without requiring knowledge of `LiveLoad`.

  An example of writing the data to a file to be analyzed later would look something like the following:

  ```elixir
  results = LiveLoad.run(
    otp_app: :my_app,
    users: 10_000,
    distributed?: true,
    flame_backend: FLAME.FlyBackend,
    cluster_opts: [
      flame_backend_opts: [app: :live_load, cpus: 8, memory_mb: 16 * 1024],
      max_allowed_nodes: 100
    ]
  )

  results
  |> Enum.map(fn
    # The scenario name is encapsulated within the result, so we don't need it on success
    {_scenario, %LiveLoad.Result{} = result} -> result
    # Format the errors as maps for JSON serialization
    {scenario, {:error, reason}} -> %{scenario: inspect(scenario), error: inspect(reason)}
  end)
  |> then(&File.write!("./liveload_results.json", JSON.encode_to_iodata!(&1)))
  ```

  For more information about what data is contained in the result, see the `LiveLoad.Result` module.
  """
  @spec run(opts :: [option()]) :: %{Scenario.t() => scenario_result()}
  def run(opts \\ []) do
    {single_scenario, opts} = Keyword.pop(opts, :scenario)
    {list_of_scenarios, opts} = Keyword.pop(opts, :scenarios)
    {otp_app, opts} = Keyword.pop(opts, :otp_app)
    scenarios = Discovery.resolve(single_scenario, list_of_scenarios, otp_app)

    {run_config, runner_opts} = build_options(opts)
    Map.new(scenarios, &{&1, run_scenario(&1, run_config, runner_opts)})
  end

  defp run_scenario(scenario, run_config, opts) do
    with {:ok, _topology_pid} <- LiveLoad.Topology.setup(scenario),
         {:ok, results} <- do_scenario(scenario, run_config[:distributed?], run_config, opts) do
      LiveLoad.Result.new(scenario, results)
    end
  after
    LiveLoad.Topology.teardown(scenario)
  end

  defp do_scenario(scenario, distributed?, run_config, opts)

  defp do_scenario(scenario, false, run_config, opts) do
    scenario_duration = Keyword.fetch!(opts, :scenario_duration)
    users = Keyword.fetch!(run_config, :users)
    timeout = collector_timeout(scenario_duration)

    case LiveLoad.Topology.run(scenario, users, opts, timeout) do
      {:ok, _results} = ok -> ok
      {:error, _reason} = error -> error
    end
  end

  defp do_scenario(scenario, true, run_config, opts) do
    users = Keyword.fetch!(run_config, :users)
    browser_connection_adapter = Keyword.fetch!(opts, :browser_connection_adapter)
    scenario_duration = Keyword.fetch!(opts, :scenario_duration)
    timeout = collector_timeout(scenario_duration)

    cluster_opts = Keyword.fetch!(run_config, :cluster_opts)
    flame_backend = Keyword.fetch!(run_config, :flame_backend)
    validate_flame_backend!(flame_backend)

    with {:ok, %Cluster{} = cluster} <-
           Cluster.prepare(scenario, users, browser_connection_adapter, flame_backend, cluster_opts),
         :ok <- LiveLoad.Topology.connect_amoc_cluster(scenario, cluster) do
      LiveLoad.Topology.run_distributed(scenario, cluster, users, opts, timeout)
    end
  end

  defp build_options(opts) do
    base_run_config = base_run_config()
    {run_config_overrides, opts} = Keyword.split_with(opts, fn {k, _v} -> Keyword.has_key?(base_run_config, k) end)
    run_config = Keyword.merge(base_run_config, run_config_overrides)

    base_runner_opts = base_runner_opts()
    {runner_opts_overrides, opts} = Keyword.split_with(opts, fn {k, _v} -> Keyword.has_key?(base_runner_opts, k) end)
    runner_opts = Keyword.merge(base_runner_opts, runner_opts_overrides)
    Enum.each([:iteration_timeout, :scenario_duration], &validate_timeout!(&1, Keyword.fetch!(runner_opts, &1)))

    {run_config, Keyword.put(runner_opts, :scenario_config_opts, opts)}
  end

  defp base_run_config do
    [users: 1, distributed?: false, cluster_opts: [], flame_backend: :unset]
  end

  defp base_runner_opts do
    [
      browser_connection_adapter: LiveLoad.Browser.Connection.Playwright,
      browser_connection_opts: [],
      iteration_timeout: to_timeout(minute: 2),
      scenario_duration: to_timeout(minute: 10)
    ]
  end

  defp validate_flame_backend!(:unset) do
    raise ArgumentError, "`:flame_backend` must be set when running a distributed load test."
  end

  defp validate_flame_backend!(module) when is_atom(module) do
    :ok
  end

  defp validate_timeout!(timeout_name, :infinity) do
    raise ArgumentError, "#{timeout_name} must be a concrete timeout and not `:infinity`."
  end

  defp validate_timeout!(_timeout_name, timeout) when is_integer(timeout) do
    :ok
  end

  defp collector_timeout(timeout) when is_integer(timeout), do: timeout + to_timeout(minute: 5)
end
