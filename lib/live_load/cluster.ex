defmodule LiveLoad.Cluster do
  @moduledoc """
  `LiveLoad.Cluster` defines the creation of an ephemeral cluster of nodes (via `FLAME`) that `LiveLoad` runs its scenarios on.

  A cluster is started for each run of a scenario. It is initialized eagerly by placing `FLAME.Trackable` resources on each node
  and ensuring that a node can have a maximum concurrency of 1, to ensure that only a single FLAME process is run on each node.

  The cluster initialization goes through optimization phases by checking the expected resource usage of a browser and calculating
  how many nodes will be necessary based on the node's actual resource availability. A `LiveLoad.Browser.Connection` must provide 3
  callbacks: `c:LiveLoad.Browser.Connection.browser_contexts_per_core/0`, `c:LiveLoad.Browser.Connection.browser_memory_usage_bytes/0`
  and `c:LiveLoad.Browser.Connection.context_memory_usage_bytes/0` to allow the cluster initialization to calculate how many nodes
  are necessary in order to pre-warm the pool. If the amount of nodes necessary exceeds the configured `max_allowed_nodes`, an error
  will be returned and the scenario will not be run.
  """

  alias __MODULE__

  @typedoc """
  A module implementing the `FLAME.Backend` behaviour.
  """
  @type flame_backend :: module()

  @typedoc """
  Options passed to the given `t:flame_backend/0` on initialization of the `FLAME.Pool`.

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
  determined by the `c:LiveLoad.Browser.Connection.browser_contexts_per_core/0`,
  `c:LiveLoad.Browser.Connection.browser_memory_usage_bytes/0` and `c:LiveLoad.Browser.Connection.context_memory_usage_bytes/0`
  callbacks on the selected `LiveLoad.Browser.Connection` implementation for this run.
  """
  @type not_enough_nodes_error() :: {:error, {:necessary_nodes_exceeds_max_allowed_nodes, necessary :: pos_integer()}}

  @typedoc """
  An error returned from the cluster initialization when the node started by the given `FLAME.Backend` implementation
  and the given `t:flame_pool_opts_opt/0` options is too small to actually handle creating a browser on the node.

  This is determined by the `LiveLoad.Cluster.Node` started during the cluster initialization.
  """
  @type node_too_small_error() :: {:error, :node_too_small}

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
          | node_too_small_error()
          | cluster_node_creation_timeout_error()
          | {:error, term()}

  @type t() :: %__MODULE__{
          pool_name: atom(),
          pool_nodes: [Cluster.Node.t()],
          pool_node_names: [node()]
        }

  @enforce_keys [:pool_name]
  defstruct [:pool_name, pool_nodes: [], pool_node_names: []]

  @doc false
  @spec prepare(
          scenario :: LiveLoad.Scenario.t(),
          users :: pos_integer(),
          browser_connection_adapter :: LiveLoad.Browser.Connection.t(),
          flame_backend :: flame_backend(),
          opts :: [option()]
        ) :: {:ok, t()} | cluster_initialization_error()
  def prepare(scenario, users, browser_connection_adapter, flame_backend, opts) do
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

    pool_opts =
      flame_pool_opts
      |> Keyword.merge(base_pool_opts(max_allowed_nodes))
      |> Keyword.put(:backend, {flame_backend, flame_backend_opts})

    LiveLoad.Topology.prepare_cluster(scenario, pool_opts, users, browser_connection_adapter, max_allowed_nodes)
  end

  defp base_pool_opts(max) do
    [max_concurrency: 1, track_resources: true, min: 0, max: max, single_use: false]
  end
end
