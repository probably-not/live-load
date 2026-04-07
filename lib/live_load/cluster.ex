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

  @type t() :: %__MODULE__{
          pool_pid: pid(),
          pool_nodes: [node()]
        }

  @enforce_keys [:pool_pid, :pool_nodes]
  defstruct [:pool_pid, :pool_nodes]

  @doc false
  @spec start_link(
          scenario :: LiveLoad.Scenario.t(),
          users :: pos_integer(),
          browser_connection_adapter :: LiveLoad.Browser.Connection.t(),
          flame_backend :: flame_backend(),
          opts :: [option()]
        ) ::
          {:ok, t()} | {:error, :scenario_is_already_running} | {:error, term()}
  def start_link(scenario, _users, _browser_connection_adapter, flame_backend, opts) do
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
    case start_flame_pool(scenario, Keyword.put(pool_opts, :backend, {flame_backend, flame_backend_opts})) do
      {:ok, pid} when is_pid(pid) -> {:ok, %__MODULE__{pool_pid: pid, pool_nodes: []}}
      {:error, {:already_started, _pid}} -> {:error, :scenario_is_already_running}
      {:error, _reason} = error -> error
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

  defp base_pool_opts(name, max) do
    [name: name, max_concurrency: 1, track_resources: true, min: 0, max: max, single_use: false]
  end

  defp start_flame_pool(name, opts) do
    DynamicSupervisor.start_child(
      {:via, PartitionSupervisor, {LiveLoad.Cluster.DynamicSupervisor, name}},
      {FLAME.Pool.start_link(opts), opts}
    )
  end
end
