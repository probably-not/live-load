defmodule LiveLoad.Topology do
  @moduledoc false

  use Supervisor

  alias __MODULE__

  def setup(scenario) do
    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {LiveLoad.Topology.DynamicSupervisor, scenario}},
           {Topology, scenario}
         ) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :scenario_is_already_running}
      {:error, _reason} = error -> error
    end
  end

  def teardown(scenario) do
    with {:lookup, [{pid, _}]} <- {:lookup, Registry.lookup(LiveLoad.Registry, scenario)},
         :ok <-
           DynamicSupervisor.terminate_child(
             {:via, PartitionSupervisor, {LiveLoad.Topology.DynamicSupervisor, scenario}},
             pid
           ) do
      :ok
    else
      {:lookup, []} -> {:error, :scenario_not_running}
      {:error, :not_found} -> {:error, :scenario_not_running}
    end
  end

  def run(scenario, users, distributed?, opts) do
    supervisor = supervisor_name(scenario)
    Topology.AmocPeer.run_scenario(amoc_peer_pid!(supervisor), scenario, distributed?, users, opts)
  end

  def start_flame_pool(scenario, opts) do
    supervisor = supervisor_name(scenario)
    Topology.Cluster.start_flame_pool(cluster_pid!(supervisor), opts)
  end

  def start_link(scenario) do
    # I probably don't really need a registry here if I'm just using the scenario, since the scenario is a module name.
    # I could just use the atom directly... But it feels weird to use the scenario as a name directly on the topology
    # when the topology is not actually the scenario, it's the entire topology of the load test.
    Supervisor.start_link(__MODULE__, scenario, name: supervisor_name(scenario))
  end

  @impl true
  def init(_scenario) do
    children = [
      Topology.AmocPeer.child_spec([], id: :amoc_peer, restart: :temporary, significant: true),
      Supervisor.child_spec(Topology.Cluster, id: :cluster, restart: :temporary, significant: true)
    ]

    Supervisor.init(children, strategy: :one_for_one, auto_shutdown: :any_significant)
  end

  defp cluster_pid!(supervisor) do
    case LiveLoad.SupUtils.find_child(supervisor, :cluster) do
      cluster when is_pid(cluster) -> cluster
      nil -> raise RuntimeError, "Topology does not contain the cluster child process"
    end
  end

  defp amoc_peer_pid!(supervisor) do
    case LiveLoad.SupUtils.find_child(supervisor, :amoc_peer) do
      amoc_peer when is_pid(amoc_peer) -> amoc_peer
      nil -> raise RuntimeError, "Topology does not contain the amoc_peer child process"
    end
  end

  defp supervisor_name(name_or_pid)
  defp supervisor_name(scenario) when is_atom(scenario), do: {:via, Registry, {LiveLoad.Registry, scenario}}
  defp supervisor_name(pid) when is_pid(pid), do: pid
end
