defmodule LiveLoad do
  @moduledoc """
  #{"./README.md" |> Path.expand() |> File.read!() |> String.split("<!-- README START -->") |> Enum.at(1) |> String.split("<!-- README END -->") |> List.first() |> String.trim()}
  """

  alias LiveLoad.Browser
  alias LiveLoad.Cluster
  alias LiveLoad.Scenario
  alias LiveLoad.Scenario.Discovery
  alias LiveLoad.Telemetry.Collector

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
  Configures the node list for a distributed load test directly.

  This is mostly used for internal testing and demos in order to pass in a ready made cluster of nodes
  instead of waiting for the nodes to be allocated by the given `t:flame_backend_opt/0`.

  Typical users should avoid passing this in directly, as it bypasses the cluster sizing checks that ensure
  the cluster has proper resources available for the load test to run.
  """
  @type cluster_nodes_opt() :: {:cluster_nodes, [node()]}

  @typedoc """
  Initialization options for running a `LiveLoad.Scenario`.

  These are split between options for the overall run configuration (`t:distributed_run_opt/0`, `t:users_count_opt/0`,
  `t:flame_backend_opt/0`, `t:cluster_opts_opt/0`, `t:cluster_nodes_opt/0`), options for the runner itself
  (`t:browser_connection_adapter_opt/0`, `t:scenario_iteration_timeout_opt/0`, `t:scenario_duration_opt/0`)
  and any other options that should be passed in as configuration to the scenario `c:LiveLoad.Scenario.config/1` callback.
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
          | cluster_nodes_opt()
          | {atom(), term()}

  @typedoc """
  The result of a `LiveLoad.Scenario` run returned by `LiveLoad.run/1`.

  This may either be a `LiveLoad.Result` or an error. If the given `t:distributed_run_opt/0`
  is set to `true`, the error may include one of the possible `t:Cluster.cluster_initialization_error/0` errors.
  """
  @type scenario_result() :: LiveLoad.Result.t() | Cluster.cluster_initialization_error() | {:error, term()}

  @doc """
  Run all of the `LiveLoad.Scenario` modules in this project.

  Scenarios are automatically discovered.
  They are run using FLAME and `:amoc`.

  TODO: Give actual documentation here!
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
    Application.stop(:amoc)
    Application.ensure_all_started(:amoc)

    case do_scenario(scenario, run_config[:distributed?], run_config, opts) do
      {:ok, results} -> LiveLoad.Result.new(scenario, results)
      {:error, _reason} = error -> error
    end
  after
    Application.stop(:amoc)
  end

  defp do_scenario(scenario, distributed?, run_config, opts)

  defp do_scenario(scenario, false, run_config, opts) do
    scenario_duration = Keyword.fetch!(opts, :scenario_duration)
    users = Keyword.fetch!(run_config, :users)

    with {:ok, collector_pid} <- Collector.start_link([node()]),
         :ok <- :amoc.do(scenario, users, Keyword.put(opts, :collector_pid, collector_pid)) do
      timeout = collector_timeout(scenario_duration)
      Collector.wait_for_completion(collector_pid, timeout)
    end
  after
    :amoc.stop()
  end

  defp do_scenario(scenario, true, run_config, opts) do
    if nodes = run_config[:cluster_nodes] do
      do_distributed_scenario_with_nodes(nodes, scenario, run_config, opts)
    else
      do_distributed_scenario_with_flame(scenario, run_config, opts)
    end
  after
    :amoc.stop()
  end

  defp do_distributed_scenario_with_nodes(nodes, scenario, run_config, opts) do
    users = Keyword.fetch!(run_config, :users)
    scenario_duration = Keyword.fetch!(opts, :scenario_duration)

    with {:ok, collector_pid} <- Collector.start_link(nodes),
         :ok <- :amoc_cluster.connect_nodes(nodes),
         {:ok, _users} <- :amoc_dist.do(scenario, users, opts) do
      timeout = collector_timeout(scenario_duration)
      Collector.wait_for_completion(collector_pid, timeout)
    end
  end

  defp do_distributed_scenario_with_flame(scenario, run_config, opts) do
    users = Keyword.fetch!(run_config, :users)
    browser_connection_adapter = Keyword.fetch!(opts, :browser_connection_adapter)
    scenario_duration = Keyword.fetch!(opts, :scenario_duration)

    cluster_opts = Keyword.fetch!(run_config, :cluster_opts)
    flame_backend = Keyword.fetch!(run_config, :flame_backend)
    validate_flame_backend!(flame_backend)

    with {:ok, %Cluster{} = cluster} <-
           Cluster.start_link(scenario, users, browser_connection_adapter, flame_backend, cluster_opts),
         {:ok, collector_pid} <- Collector.start_link(cluster.pool_nodes),
         :ok <- :amoc_cluster.connect_nodes(cluster.pool_nodes),
         {:ok, _users} <- :amoc_dist.do(scenario, users, opts) do
      timeout = collector_timeout(scenario_duration)
      Collector.wait_for_completion(collector_pid, timeout)
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
