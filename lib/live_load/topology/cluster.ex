defmodule LiveLoad.Topology.Cluster do
  @moduledoc false

  use Supervisor

  alias LiveLoad.Cluster

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(_opts) do
    Supervisor.init([], strategy: :one_for_one, auto_shutdown: :any_significant)
  end

  def setup_flame_pool(supervisor, pool_opts) do
    case start_flame_pool(supervisor, pool_opts) do
      # The pid of the cluster is linked and managed by the topology supervision,
      # so we can just ignore it here.
      {:ok, _pid} -> :ok
      # There shouldn't be any of the already_started/already_present errors for this from FLAME.Pool's startup,
      # since the whole topology is already unique, so I'm not going to try and catch it. If we do get to that
      # situation something has probably drifted and the system is not in a clean state anyways.
      {:error, _reason} = error -> error
    end
  end

  def teardown_cluster(supervisor) do
    Supervisor.terminate_child(supervisor, :pool)
  end

  defp start_flame_pool(supervisor, opts) do
    wrapped = Supervisor.child_spec({FLAME.Pool, opts}, id: :pool, restart: :temporary)
    Supervisor.start_child(supervisor, wrapped)
  end

  def preconnect_mesh(%Cluster{} = cluster) do
    results =
      cluster.pool_nodes
      |> Task.async_stream(
        fn %Cluster.Node{} = cluster_node ->
          Cluster.Node.preconnect(cluster_node, cluster.pool_node_names, to_timeout(minute: 1))
        end,
        max_concurrency: min(8, max(length(cluster.pool_nodes), 1)),
        timeout: :infinity
      )
      |> Enum.zip(cluster.pool_nodes)
      |> Map.new(fn {{:ok, node_results}, %Cluster.Node{node: node}} ->
        {node, node_results}
      end)

    failures =
      for {node, node_results} <- results,
          bad_peers = Enum.reject(List.wrap(node_results), &match?({_, true}, &1)),
          bad_peers != [],
          into: %{},
          do: {node, bad_peers}

    if map_size(failures) == 0 do
      :ok
    else
      {:error, {:preconnect_mesh_failed, failures}}
    end
  end

  def seed_amoc_cluster(amoc_master_peer_node, %Cluster{} = cluster) do
    seeds = [amoc_master_peer_node | cluster.pool_node_names]

    results =
      cluster.pool_nodes
      |> Map.new(fn %Cluster.Node{} = cluster_node ->
        {cluster_node.node, Cluster.Node.seed_amoc_cluster(cluster_node, seeds, to_timeout(minute: 2))}
      end)
      |> Map.put(
        amoc_master_peer_node,
        :rpc.call(
          amoc_master_peer_node,
          LiveLoad.Cluster.AmocSeed,
          :seed_amoc_cluster_on_node,
          [seeds],
          to_timeout(minute: 2)
        )
      )

    failures =
      for {node, ping_results} <- results,
          bad = Enum.reject(List.wrap(ping_results), &match?({_, :pong}, &1)),
          bad != [],
          into: %{},
          do: {node, bad}

    if map_size(failures) == 0 do
      :ok
    else
      {:error, {:seed_amoc_cluster_failed, failures}}
    end
  end

  def prime_cluster(cluster_pool_name, users, browser_connection_adapter, max_allowed_nodes) do
    with %Cluster.Node{} = initial_cluster_node <- wrapped_node_create(cluster_pool_name, 10),
         {:ok, necessary_nodes} <-
           validate_cluster_sizing(initial_cluster_node, users, browser_connection_adapter, max_allowed_nodes) do
      spin_up_nodes(necessary_nodes - 1, cluster_pool_name, [initial_cluster_node])
    end
  end

  defp spin_up_nodes(count, cluster_pool_name, initial_nodes) do
    results =
      1..count//1
      |> Task.async_stream(
        fn _ -> wrapped_node_create(cluster_pool_name, 10) end,
        # TODO: This should probably be configurable somehow... but I don't want to
        # start propagating opts right now.
        max_concurrency: min(8, max(count, 1)),
        # FLAME.call inside wrapped_node_create already inherits FLAME's timeout,
        # so setting the timeout to `:infinity` here should probably be safe, and
        # ensure that the task completes based on the configured timeout.
        timeout: :infinity,
        ordered: false
      )
      |> Enum.to_list()

    Enum.reduce_while(results, {:ok, initial_nodes}, fn
      {:ok, %Cluster.Node{} = node}, {:ok, nodes} -> {:cont, {:ok, [node | nodes]}}
      {:ok, {:error, _} = error}, _acc -> {:halt, error}
    end)
  end

  defp wrapped_node_create(pool_name, attempts_left, errors \\ [])

  defp wrapped_node_create(_pool_name, 0, errors) do
    {:error, {:retries_exhausted, Enum.reverse(errors)}}
  end

  defp wrapped_node_create(pool_name, attempts_left, errors) do
    FLAME.call(pool_name, &Cluster.Node.new!/0, track_resources: true)
  rescue
    exception -> {:error, exception}
  catch
    :exit, {:timeout, {FLAME.Pool, :call, _}} ->
      wrapped_node_create(pool_name, attempts_left - 1, [{:exit, :timeout} | errors])

    :exit, {:noproc, {FLAME.Pool, :call, _}} ->
      {:error, :cluster_name_invalid}

    :exit, reason ->
      {:exit, reason}
  end

  defp validate_cluster_sizing(%Cluster.Node{} = cluster_node, users, browser_connection_adapter, max_allowed_nodes) do
    case Cluster.Sizing.calculate_possible_users_per_node(cluster_node, browser_connection_adapter) do
      0 ->
        {:error, :node_too_small}

      users_per_node ->
        necessary_nodes = ceil(users / users_per_node)

        if necessary_nodes > max_allowed_nodes do
          {:error, {:necessary_nodes_exceeds_max_allowed_nodes, necessary_nodes}}
        else
          {:ok, necessary_nodes}
        end
    end
  end
end
