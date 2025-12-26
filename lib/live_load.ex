defmodule LiveLoad do
  @moduledoc """
  #{"./README.md" |> Path.expand() |> File.read!() |> String.split("<!-- README START -->") |> Enum.at(1) |> String.split("<!-- README END -->") |> List.first() |> String.trim()}
  """

  @type option() :: {atom(), term()}
  @type opts() :: [option()]

  # TODO: Spec results
  @type results() :: term()

  @spec run(opts :: opts()) :: {:ok, results()} | {:error, term()}
  def run(opts) do
    Application.stop(:amoc)
    Application.ensure_all_started(:amoc)
    scenarios = discover_scenarios(opts)
    # TODO: Start up FLAME Pool (or Pools, if we have regionality involved?)
    Enum.each(scenarios, &run_scenario/1)
    {:ok, nil}
  end

  defp discover_scenarios(_opts) do
    [LiveLoad.Scenario.Example]
  end

  # TODO: How are we running scenarios?
  # - Raise FLAME nodes with Trackable that stays alive until we are done running the test
  # - Collect all nodes from FLAME pools.
  # - On the controller node, run `:amoc_cluster.connect_nodes(flame_node_list)`
  # - On the controller node, run `:amoc_dist.do(scenario_mod, user_count, settings)`
  defp run_scenario(scenario) do
    Application.stop(:amoc)
    Application.ensure_all_started(:amoc)
    :amoc.do(scenario, 10, runner_pid: self())
  after
    # TODO: Wrap this up and wait for all of the nodes in the test to complete
    receive do
      {:scenario_timeout, _scenario, _completed_node} ->
        :ok
    end

    Application.stop(:amoc)
  end
end
