defmodule LiveLoad do
  @moduledoc """
  #{"./README.md" |> Path.expand() |> File.read!() |> String.split("<!-- README START -->") |> Enum.at(1) |> String.split("<!-- README END -->") |> List.first() |> String.trim()}
  """

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

  These are split between options for the runner itself(`t:browser_connection_adapter_opt/0`, `t:scenario_timeout_opt/0`)
  and any other options that should be passed in as configuration to the scenario `c:LiveLoad.Scenario.config/1` callback.
  """
  @type option() :: browser_connection_adapter_opt() | scenario_timeout_opt() | heartbeat_seconds_opt() | {atom(), term()}

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
    # TODO: Start up FLAME Pool (or Pools, if we have regionality involved?)
    Enum.map(scenarios, &{&1, run_scenario(&1, build_options(opts))})
  end

  defp discover_scenarios(_opts) do
    [LiveLoad.Scenario.Example]
  end

  # TODO: How are we running scenarios?
  # - Raise FLAME nodes with Trackable that stays alive until we are done running the test
  # - Collect all nodes from FLAME pools.
  # - On the controller node, run `:amoc_cluster.connect_nodes(flame_node_list)`
  # - On the controller node, run `:amoc_dist.do(scenario_mod, user_count, settings)`
  defp run_scenario(scenario, opts) do
    Application.stop(:amoc)
    Application.ensure_all_started(:amoc)

    case :amoc.do(scenario, 1, opts) do
      :ok ->
        wait(scenario)

      # `:amoc_dist.do` returns a tuple of `{:ok, any()}`,
      # so we handle it in the same way as a normal `:ok` here.
      {:ok, _} ->
        wait(scenario)

      {:error, reason} ->
        {:error, reason}

      # This is a catch for the current version of AMoC.
      # It does not extract the error value properly.
      # When the new release happens, we can remove this and just rely on the above match.
      {{:error, reason}, _} ->
        {:error, reason}
    end
  after
    Application.stop(:amoc)
  end

  defp wait(scenario) do
    # TODO: Wrap this up and wait for all of the nodes in the test to complete
    receive do
      {:scenario_timeout, ^scenario, _completed_node} ->
        :ok
    end
  end

  defp build_options(nil) do
    base_options()
  end

  defp build_options(opts) do
    {runner_opts, scenario_config_opts} =
      Enum.reduce(
        [
          {:timeout, :scenario_timeout},
          {:heartbeat, :heartbeat_timeout_seconds},
          {:browser_connection_adapter, :browser_connection_adapter}
        ],
        {base_options(), opts},
        fn {key, replacement}, {runner_opts, scenario_config_opts} ->
          {opt, rest} = Keyword.pop(scenario_config_opts, key, :error)

          if opt == :error do
            {runner_opts, rest}
          else
            {Keyword.put(runner_opts, replacement, opt), rest}
          end
        end
      )

    Keyword.put(runner_opts, :scenario_config_opts, scenario_config_opts)
  end

  defp base_options do
    [runner_pid: self(), browser_connection_adapter: LiveLoad.Browser.Connection.Playwright]
  end
end
