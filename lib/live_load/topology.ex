defmodule LiveLoad.Topology do
  @moduledoc false

  use Supervisor

  alias __MODULE__
  alias LiveLoad.Telemetry.Collector

  def setup(scenario, topology_opts \\ []) do
    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {LiveLoad.Topology.DynamicSupervisor, scenario}},
           Supervisor.child_spec({__MODULE__, {scenario, topology_opts}}, restart: :temporary)
         ) do
      {:ok, pid} when is_pid(pid) ->
        # We link to the calling process so that if the calling process has any issues and exits, we close out the resources.
        # This should probably be passed in as an option somewhere instead of forcing the link.
        Process.link(pid)
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        {:error, :scenario_is_already_running}

      {:error, _reason} = error ->
        error
    end
  end

  def teardown(scenario) do
    with {:lookup, [{pid, _}]} <- {:lookup, Registry.lookup(LiveLoad.Registry, scenario)},
         # Because we linked in the setup, we need to unlink. Otherwise the termination will kill our calling process... not good.
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
    runner_pid = runner_pid!(supervisor)

    amoc_peer_node = Topology.AmocPeer.peer(amoc_peer_pid)
    {browser_connection_adapter, opts} = Keyword.pop!(opts, :browser_connection_adapter)
    {browser_connection_opts, opts} = Keyword.pop!(opts, :browser_connection_opts)
    {scenario_setup_timeout, opts} = Keyword.pop(opts, :scenario_setup_timeout, to_timeout(minute: 2))

    :ok =
      Topology.Runner.setup!(
        runner_pid,
        amoc_peer_node,
        browser_connection_adapter,
        browser_connection_opts,
        collector_pid,
        scenario_setup_timeout
      )

    try do
      with :ok <- Topology.AmocPeer.register_scenarios_to_amoc(amoc_peer_pid, [scenario]),
           :ok <- Collector.watch_cluster(collector_pid, [node()]),
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
    runner_pid = runner_pid!(supervisor)

    {browser_connection_adapter, opts} = Keyword.pop!(opts, :browser_connection_adapter)
    {browser_connection_opts, opts} = Keyword.pop!(opts, :browser_connection_opts)
    {scenario_setup_timeout, opts} = Keyword.pop(opts, :scenario_setup_timeout, to_timeout(minute: 2))

    :ok =
      Enum.each(
        cluster_nodes,
        &Topology.Runner.setup!(
          runner_pid,
          &1,
          browser_connection_adapter,
          browser_connection_opts,
          collector_pid,
          scenario_setup_timeout
        )
      )

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

    with :ok <- Topology.AmocPeer.register_scenarios_to_amoc(amoc_peer_pid, [scenario]),
         :ok <- Topology.AmocPeer.connect_amoc_cluster(amoc_peer_pid, nodes) do
      Topology.AmocPeer.distribute_scenarios_to_amoc_cluster(amoc_peer_pid, nodes)
    end
  end

  def start_link({scenario, topology_opts}) do
    # I probably don't really need a registry here if I'm just using the scenario, since the scenario is a module name.
    # I could just use the atom directly... But it feels weird to use the scenario as a name directly on the topology
    # when the topology is not actually the scenario, it's the entire topology of the load test.
    Supervisor.start_link(__MODULE__, topology_opts, name: supervisor_name(scenario))
  end

  @impl true
  def init(topology_opts) do
    amoc_peer_opts = topology_opts[:amoc_peer_opts] || []

    children = [
      Topology.AmocPeer.child_spec(amoc_peer_opts, id: :amoc_peer, restart: :temporary, significant: true),
      Supervisor.child_spec(Topology.Runner, id: :runner, restart: :temporary, significant: true),
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

  defp runner_pid!(supervisor) do
    case LiveLoad.SupUtils.find_child(supervisor, :runner) do
      collector when is_pid(collector) -> collector
      nil -> raise RuntimeError, "Topology does not contain the runner child process"
    end
  end

  defp supervisor_name(name_or_pid)
  defp supervisor_name(scenario) when is_atom(scenario), do: {:via, Registry, {LiveLoad.Registry, scenario}}
  defp supervisor_name(pid) when is_pid(pid), do: pid
end
