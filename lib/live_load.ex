defmodule LiveLoad do
  @moduledoc """
  #{"./README.md" |> Path.expand() |> File.read!() |> String.split("<!-- README START -->") |> Enum.at(1) |> String.split("<!-- README END -->") |> List.first() |> String.trim()}
  """

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
  Defines the overall timeout for a scenario.

  If this timeout is reached and the scenario has not completed, it will be killed and reported as a failure.

  Defaults to 10 minutes.
  """
  @type scenario_timeout_opt() :: {:timeout, timeout()}

  @typedoc """
  Defines the heartbeat signal timeout for the scenario runner in seconds.

  It is available for testing and tuning purposes.

  **This is an internal option that should almost certainly never be used by end users.**

  The scenario runner reports a heartbeat every time this interval is hit.
  This heartbeat is used by [AMoC's Coordinator](`:amoc_coordinator`) in order to track which processes are running.
  """
  @type heartbeat_seconds_opt() :: {:heartbeat, pos_integer()}

  @typedoc """
  Initialization options for running a `LiveLoad.Scenario`.

  These are split between options for the overall run configuration (`t:distributed_run_opt/0`, `t:users_count_opt/0`),
  options for the runner itself (`t:browser_connection_adapter_opt/0`, `t:scenario_timeout_opt/0`)
  and any other options that should be passed in as configuration to the scenario `c:LiveLoad.Scenario.config/1` callback.
  """
  @type option() ::
          distributed_run_opt()
          | users_count_opt()
          | browser_connection_adapter_opt()
          | scenario_timeout_opt()
          | heartbeat_seconds_opt()
          | {atom(), term()}

  @typedoc """
  TODO: Spec results
  """
  @type result() :: {LiveLoad.Scenario.t(), term()}

  @doc """
  Run all of the `LiveLoad.Scenario` modules in this project.

  Scenarios are automatically discovered.
  They are run using FLAME and `:amoc`.

  TODO: Give actual documentation here!
  """
  @spec run(opts :: [option()]) :: [result()] | {:error, term()}
  def run(opts \\ []) do
    scenarios = discover_scenarios(opts)
    {run_config, runner_opts} = build_options(opts)
    Enum.map(scenarios, &{&1, run_scenario(&1, run_config, runner_opts)})
  end

  defp discover_scenarios(_opts) do
    [LiveLoad.Scenario.Example]
  end

  defp run_scenario(scenario, run_config, opts) do
    Application.stop(:amoc)
    Application.ensure_all_started(:amoc)

    case do_scenario(scenario, run_config[:users], run_config[:distributed?], opts) do
      :ok ->
        wait(scenario)

      # `:amoc_dist.do` returns a tuple of `{:ok, any()}`,
      # so we handle it in the same way as a normal `:ok` here.
      {:ok, _} ->
        wait(scenario)

      {:error, reason} ->
        {:error, reason}
    end
  after
    Application.stop(:amoc)
  end

  defp do_scenario(scenario, users, distributed?, opts)

  defp do_scenario(scenario, users, false, opts) do
    :amoc.do(scenario, users, opts)
  end

  defp do_scenario(scenario, users, true, opts) do
    # TODO: How are we running scenarios?
    # - Raise FLAME nodes with Trackable that stays alive until we are done running the test
    # - Collect all nodes from FLAME pools.
    # - On the controller node, run `:amoc_cluster.connect_nodes(flame_node_list)`
    # - On the controller node, run `:amoc_dist.do(scenario_mod, user_count, settings)`
    :amoc_dist.do(scenario, users, opts)
  end

  defp wait(scenario) do
    # TODO: Wrap this up and wait for all of the nodes in the test to complete
    receive do
      {:scenario_timeout, ^scenario, _completed_node} ->
        :ok
    end
  end

  defp build_options(nil) do
    {base_run_config(), base_runner_options()}
  end

  defp build_options(opts) do
    {runner_opts, scenario_config_opts} =
      Enum.reduce(
        [
          {:timeout, :scenario_timeout},
          {:heartbeat, :heartbeat_timeout_seconds},
          {:browser_connection_adapter, :browser_connection_adapter}
        ],
        {base_runner_options(), opts},
        fn {key, replacement}, {runner_opts, scenario_config_opts} ->
          {opt, rest} = Keyword.pop(scenario_config_opts, key, :error)

          if opt == :error do
            {runner_opts, rest}
          else
            {Keyword.put(runner_opts, replacement, opt), rest}
          end
        end
      )

    run_config =
      Enum.reduce(base_run_config(), [], fn {key, default_value}, config ->
        value = Keyword.get(opts, key, default_value)
        Keyword.put(config, key, value)
      end)

    {run_config, Keyword.put(runner_opts, :scenario_config_opts, scenario_config_opts)}
  end

  defp base_run_config do
    [users: 1, distributed?: false]
  end

  defp base_runner_options do
    [runner_pid: self(), browser_connection_adapter: LiveLoad.Browser.Connection.Playwright]
  end
end
