defmodule LiveLoad.Cluster do
  @moduledoc """
  `LiveLoad.Cluster` defines the creation of an ephemeral cluster of nodes (via `FLAME`) that `LiveLoad` runs its scenarios on.

  A cluster is started for each run of a scenario. It is initialized eagerly by placing `FLAME.Trackable` resources on each node
  and ensuring that a node can have a maximum concurrency of 1, to ensure that only a single FLAME process is run on each node.

  The cluster initialization goes through optimization phases by checking the expected resource usage of a browser and calculating
  how many nodes will be necessary based on the node's actual resource availability. A `LiveLoad.Browser.Connection` must provide 2
  callbacks: `c:LiveLoad.Browser.Connection.browser_memory_usage_bytes/0` and `c:LiveLoad.Browser.Connection.context_memory_usage_bytes/0` to
  allow the cluster initialization to calculate how many nodes are necessary in order to pre-warm the pool. If the amount of nodes
  necessary exceeds the configured `max_allowed_nodes`, an error will be returned and the scenario will not be run.
  """

  alias __MODULE__

  @typedoc """
  A module implementing the `FLAME.Backend` behaviour.
  """
  @type flame_backend :: module()

  @typedoc """
  Options passed to the given `t:flame_backend_opt/0` on initialization of the `FLAME.Pool`.

  Defaults to an empty list.
  """
  @type flame_backend_opts_opt() :: {:flame_backend_opts, Keyword.t()}

  @typedoc """
  Defines the maximum nodes that this load test can create when setting up a cluster.

  Nodes are created eagerly on initialization of the cluster and maintained until the end
  of the load test's run. During cluster initialization, an optimization phase will be run
  to calculate the number of nodes required for this load test to complete based on the number
  of users for this load test, the resources available on a cluster node, and the resources required
  by the `LiveLoad.Browser.Connection` module used in this load test. Should the number of nodes required
  exceed the given value, an error will be returned.

  The value given to this option must be a positive integer. If a negative integer or 0 is passed in,
  an ArgumentError will be raised.

  Defaults to 100 nodes.
  """
  @type max_allowed_nodes_opt() :: {:max_allowed_nodes, pos_integer()}

  @typedoc """
  Options passed to the `FLAME.Pool` on initialization.

  The following options are automatically overridden by `LiveLoad.Cluster` and cannot be
  manually passed in:
  - `:name`
  - `:max_concurrency`
  - `:track_resources`
  - `:min`
  - `:max`
  - `:single_use`

  See `FLAME.Pool` for all other available options.

  Defaults to an empty list.
  """
  @type flame_pool_opts_opt() :: {:flame_pool_opts, Keyword.t()}

  @typedoc """
  Initialization options for running a `LiveLoad.Cluster`.
  """
  @type option() :: flame_backend_opts_opt() | max_allowed_nodes_opt() | flame_pool_opts_opt()

  @typedoc """
  An error returned from the cluster initialization when the scenario is currently running and a new pool cannot be started.

  This error is a limitation of FLAME, as FLAME requires atoms as pool names due to the usage of named ETS tables.
  """
  @type scenario_already_running_error() :: {:error, :scenario_is_already_running}

  @typedoc """
  An error returned from the cluster initialization when the given `t:max_allowed_nodes_opt/0`
  is smaller than the calculated necessary nodes needed to run the load test on the FLAME nodes
  configured by the the given FLAME configurations.

  The calculation of necessary nodes is a heuristic based on the expected resource usage per user process
  determined by the `c:LiveLoad.Browser.Connection.browser_memory_usage_bytes/0` and
  `c:LiveLoad.Browser.Connection.context_memory_usage_bytes/0` callbacks on the selected
  `LiveLoad.Browser.Connection` implementation for this run.
  """
  @type not_enough_nodes_error() :: {:error, {:necessary_nodes_exceeds_max_allowed_nodes, necessary :: pos_integer()}}

  @typedoc """
  An error returned from the cluster initialization when the creation of a cluster node takes longer than the configured
  timeout for the `FLAME.Pool`.
  """
  @type cluster_node_creation_timeout_error() :: {:error, :cluster_node_creation_timeout}

  @typedoc """
  An error returned from the cluster initialization when the creation of a cluster node crashes due to the `FLAME.Pool` name being invalid.
  """
  @type cluster_name_invalid_error() :: {:error, :cluster_name_invalid}

  @type cluster_initialization_error() ::
          scenario_already_running_error()
          | not_enough_nodes_error()
          | cluster_node_creation_timeout_error()
          | {:error, term()}

  @type t() :: %__MODULE__{
          pool_name: atom(),
          pool_pid: pid(),
          pool_nodes: [Cluster.Node.t()]
        }

  @enforce_keys [:pool_name, :pool_pid, :pool_nodes]
  defstruct [:pool_name, :pool_pid, :pool_nodes]

  @doc false
  @spec start_link(
          scenario :: LiveLoad.Scenario.t(),
          users :: pos_integer(),
          browser_connection_adapter :: LiveLoad.Browser.Connection.t(),
          flame_backend :: flame_backend(),
          opts :: [option()]
        ) ::
          {:ok, t()} | cluster_initialization_error()
  def start_link(scenario, users, browser_connection_adapter, flame_backend, opts) do
    opts = Keyword.validate!(opts, flame_backend_opts: [], max_allowed_nodes: 100, flame_pool_opts: [])

    max_allowed_nodes = Keyword.fetch!(opts, :max_allowed_nodes)

    if max_allowed_nodes <= 0 do
      raise ArgumentError, """
      The `:max_allowed_nodes` option must be set to a number greater than 0.

      The value it is currently set to is #{inspect(max_allowed_nodes)}.
      """
    end

    flame_backend_opts = Keyword.fetch!(opts, :flame_backend_opts)
    flame_pool_opts = Keyword.fetch!(opts, :flame_pool_opts)

    pool_opts = Keyword.merge(flame_pool_opts, base_pool_opts(scenario, max_allowed_nodes))

    # TODO: I'm using the scenario module as the name because name is required to be an atom. Is this unique enough?
    # Probably yes for now... but I'll probably need to add some sort of locking mechanism at some point.
    # `:amoc` is a "global" process, so I can only run one scenario at a time anyways. Maybe I can set up
    # a simple queue with a GenServer so that I only run one at a time and the scenario will be unique enough at that point.

    # TODO: If the pool has started and the priming fails, I need to stop the pool properly.
    with {:ok, pid} <- start_flame_pool(scenario, Keyword.put(pool_opts, :backend, {flame_backend, flame_backend_opts})),
         cluster = %__MODULE__{pool_name: scenario, pool_pid: pid, pool_nodes: []},
         {:ok, %__MODULE__{} = cluster} <- prime_cluster(cluster, users, browser_connection_adapter, max_allowed_nodes) do
      {:ok, cluster}
    end
  end

  @doc false
  @spec stop(scenario :: LiveLoad.Scenario.t(), pool_pid :: pid()) :: :ok | {:error, :not_found}
  def stop(scenario, pool_pid) do
    DynamicSupervisor.terminate_child(
      {:via, PartitionSupervisor, {LiveLoad.Cluster.DynamicSupervisor, scenario}},
      pool_pid
    )
  end

  defp prime_cluster(%__MODULE__{} = cluster, users, browser_connection_adapter, max_allowed_nodes) do
    with %Cluster.Node{} = initial_cluster_node <- wrapped_node_create(cluster.pool_name),
         {:ok, necessary_nodes} <-
           validate_cluster_sizing(initial_cluster_node, users, browser_connection_adapter, max_allowed_nodes) do
      cluster = %{cluster | pool_nodes: [initial_cluster_node]}

      Enum.reduce_while(1..(necessary_nodes - 1), {:ok, cluster}, fn _, {:ok, %Cluster{} = acc} ->
        case wrapped_node_create(acc.pool_name) do
          %Cluster.Node{} = cluster_node -> {:cont, {:ok, %{acc | pool_nodes: [cluster_node | acc.pool_nodes]}}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp wrapped_node_create(pool_name) do
    FLAME.call(pool_name, &Cluster.Node.new!/0, track_resources: true)
  rescue
    exception -> {:error, exception}
  catch
    :exit, {:timeout, {FLAME.Pool, :call, _}} -> {:error, :cluster_node_creation_timeout}
    :exit, {:noproc, {FLAME.Pool, :call, _}} -> {:error, :cluster_name_invalid}
    :exit, reason -> {:error, reason}
  end

  defp validate_cluster_sizing(%Cluster.Node{} = cluster_node, users, browser_connection_adapter, max_allowed_nodes) do
    users_per_node = calculate_possible_users_per_node(cluster_node, browser_connection_adapter)
    necessary_nodes = ceil(users / users_per_node)

    if necessary_nodes > max_allowed_nodes do
      {:error, {:necessary_nodes_exceeds_max_allowed_nodes, necessary_nodes}}
    else
      {:ok, necessary_nodes}
    end
  end

  defp calculate_possible_users_per_node(%Cluster.Node{} = _cluster_node, browser_connection_adapter) do
    # TODO: Calculate stuff correctly
    _ = browser_connection_adapter.browser_memory_usage_bytes() + browser_connection_adapter.context_memory_usage_bytes()
    1
  end

  defp base_pool_opts(name, max) do
    [name: name, max_concurrency: 1, track_resources: true, min: 0, max: max, single_use: false]
  end

  defp start_flame_pool(name, opts) do
    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {LiveLoad.Cluster.DynamicSupervisor, name}},
           {FLAME.Pool, opts}
         ) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :scenario_is_already_running}
      {:error, _reason} = error -> error
    end
  end
end
