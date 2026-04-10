defmodule LiveLoad.Topology do
  @moduledoc false

  use Supervisor

  alias __MODULE__
  alias LiveLoad.Telemetry.Collector

  def setup(scenario) do
    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {LiveLoad.Topology.DynamicSupervisor, scenario}},
           Supervisor.child_spec({Topology, scenario}, restart: :temporary)
         ) do
      {:ok, pid} when is_pid(pid) -> Process.link(pid) and {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :scenario_is_already_running}
      {:error, _reason} = error -> error
    end
  end

  def teardown(scenario) do
    with {:lookup, [{pid, _}]} <- {:lookup, Registry.lookup(LiveLoad.Registry, scenario)},
         true <- Process.unlink(pid),
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

  def run(scenario, users, opts, timeout) do
    supervisor = supervisor_name(scenario)
    amoc_peer_pid = amoc_peer_pid!(supervisor)
    collector_pid = collector_pid!(supervisor)
    opts = Keyword.put(opts, :collector_pid, collector_pid)

    try do
      with :ok <- Collector.watch_cluster(collector_pid, [node()]),
           :ok <- Topology.AmocPeer.run_scenario(amoc_peer_pid, scenario, users, opts) do
        Collector.wait_for_completion(collector_pid, timeout)
      end
    after
      Topology.AmocPeer.stop(amoc_peer_pid, false)
    end
  end

  def run_distributed(scenario, cluster_nodes, users, opts, timeout) do
    supervisor = supervisor_name(scenario)
    amoc_peer_pid = amoc_peer_pid!(supervisor)
    collector_pid = collector_pid!(supervisor)
    opts = Keyword.put(opts, :collector_pid, collector_pid)

    try do
      with :ok <- Collector.watch_cluster(collector_pid, cluster_nodes),
           {:ok, _users} <- Topology.AmocPeer.run_distributed_scenario(amoc_peer_pid, scenario, users, opts) do
        Collector.wait_for_completion(collector_pid, timeout)
      end
    after
      Topology.AmocPeer.stop(amoc_peer_pid, true)
    end
  end

  def prepare_cluster(scenario, pool_opts, users, browser_connection_adapter, max_allowed_nodes) do
    supervisor = supervisor_name(scenario)
    cluster_pid = cluster_pid!(supervisor)

    pool_name = Module.concat([__MODULE__, FLAME.Pool, scenario])
    pool_opts = Keyword.put(pool_opts, :name, pool_name)
    cluster = %LiveLoad.Cluster{pool_name: pool_name}

    with :ok <- Topology.Cluster.setup_flame_pool(cluster_pid, pool_opts),
         {:ok, nodes} <- Topology.Cluster.prime_cluster(pool_name, users, browser_connection_adapter, max_allowed_nodes) do
      {:ok, %{cluster | pool_nodes: nodes, pool_node_names: Enum.map(nodes, & &1.node)}}
    else
      error ->
        Topology.Cluster.teardown_cluster(cluster_pid)
        error
    end
  end

  def connect_amoc_cluster(scenario, nodes) do
    supervisor = supervisor_name(scenario)
    amoc_peer_pid = amoc_peer_pid!(supervisor)
    Topology.AmocPeer.connect_amoc_cluster(amoc_peer_pid, nodes)
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
      Supervisor.child_spec(Topology.Cluster, id: :cluster, restart: :temporary, significant: true),
      Supervisor.child_spec(Collector, id: :collector, restart: :temporary, significant: true)
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

  defp collector_pid!(supervisor) do
    case LiveLoad.SupUtils.find_child(supervisor, :collector) do
      collector when is_pid(collector) -> collector
      nil -> raise RuntimeError, "Topology does not contain the collector child process"
    end
  end

  defp supervisor_name(name_or_pid)
  defp supervisor_name(scenario) when is_atom(scenario), do: {:via, Registry, {LiveLoad.Registry, scenario}}
  defp supervisor_name(pid) when is_pid(pid), do: pid
end
