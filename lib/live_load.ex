defmodule LiveLoad do
  @moduledoc """
  #{"./README.md" |> Path.expand() |> File.read!() |> String.split("<!-- README START -->") |> Enum.at(1) |> String.split("<!-- README END -->") |> List.first() |> String.trim()}
  """

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
  @type browser_connection_adapter_opt() :: {:browser_connection_adapter, LiveLoad.Browser.Connection.t()}

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

  When running a load test, the scenario's `c:LiveLoad.Scenario.run/2` callback will be run in a loop multiple times
  until this value is reached. Once reached, the runner will transition to a terminating state and wait for the latest
  iteration of the scenario to complete, and then report its completion.

  Defaults to 10 minutes.

  _Note: while the type here is set to `t:timeout/0`, the `:infinity` value is invalid and an error will be returned if it is passed._
  """
  @type scenario_duration_opt() :: {:scenario_duration, timeout()}

  @typedoc """
  Initialization options for running a `LiveLoad.Scenario`.

  These are split between options for the overall run configuration (`t:distributed_run_opt/0`, `t:users_count_opt/0`),
  options for the runner itself (`t:browser_connection_adapter_opt/0`, `t:scenario_iteration_timeout_opt/0`, `t:scenario_duration_opt/0`)
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
          | {atom(), term()}

  @doc """
  Run all of the `LiveLoad.Scenario` modules in this project.

  Scenarios are automatically discovered.
  They are run using FLAME and `:amoc`.

  TODO: Give actual documentation here!
  """
  @spec run(opts :: [option()]) :: %{Scenario.t() => LiveLoad.Result.t() | {:error, term()}}
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

    case do_scenario(scenario, run_config[:users], run_config[:distributed?], opts) do
      {:ok, results} -> LiveLoad.Result.new(scenario, results)
      {:error, _reason} = error -> error
    end
  after
    Application.stop(:amoc)
  end

  defp do_scenario(scenario, users, distributed?, opts)

  defp do_scenario(scenario, users, false, opts) do
    with {:ok, collector_pid} <- Collector.start_link([node()]),
         :ok <- :amoc.do(scenario, users, Keyword.put(opts, :collector_pid, collector_pid)) do
      timeout = collector_timeout(opts[:scenario_duration])
      Collector.wait_for_completion(collector_pid, timeout)
    end
  after
    :amoc.stop()
  end

  defp do_scenario(scenario, users, true, opts) do
    # TODO: How are we running scenarios?
    # - Raise FLAME nodes with Trackable that stays alive until we are done running the test
    # - Collect all nodes from FLAME pools.
    # - On the controller node, run `:amoc_cluster.connect_nodes(flame_node_list)`
    # - On the controller node, run `:amoc_dist.do(scenario_mod, user_count, settings)`
    :amoc_dist.do(scenario, users, opts)
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
    [users: 1, distributed?: false]
  end

  defp base_runner_opts do
    [
      browser_connection_adapter: LiveLoad.Browser.Connection.Playwright,
      iteration_timeout: to_timeout(minute: 2),
      scenario_duration: to_timeout(minute: 10)
    ]
  end

  defp validate_timeout!(timeout_name, :infinity) do
    raise ArgumentError, "#{timeout_name} must be a concrete timeout and not `:infinity`."
  end

  defp validate_timeout!(_timeout_name, timeout) when is_integer(timeout) do
    :ok
  end

  # TODO: I gotta add the scenario timeout default here shared somehow...
  defp collector_timeout(timeout)
  defp collector_timeout(nil), do: to_timeout(minute: 15)
  defp collector_timeout(timeout), do: timeout + to_timeout(minute: 5)
end
