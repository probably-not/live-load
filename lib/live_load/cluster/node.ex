defmodule LiveLoad.Cluster.Node do
  @moduledoc """
  `LiveLoad.Cluster.Node` implements the `FLAME.Trackable` protocol to allow `LiveLoad` to maintain the `FLAME.Pool` nodes for the duration of the `LiveLoad.Scenario`.
  """

  @type t() :: %__MODULE__{
          node: node(),
          ref: reference(),
          schedulers_online: pos_integer(),
          logical_processors: pos_integer() | nil,
          logical_processors_online: pos_integer() | nil,
          logical_processors_available: pos_integer() | nil,
          total_memory: pos_integer(),
          available_memory: pos_integer(),
          tracked_pid: pid() | nil
        }

  @enforce_keys [
    :node,
    :ref,
    :schedulers_online,
    :total_memory,
    :available_memory
  ]
  defstruct [
    :node,
    :ref,
    :schedulers_online,
    :logical_processors,
    :logical_processors_online,
    :logical_processors_available,
    :total_memory,
    :available_memory,
    :tracked_pid
  ]

  @doc false
  def new! do
    # Guarantee that the various applications necessary for LiveLoad are running on the node.
    # The FlamePeer library needs `:peer_applications` to define what's started on the peer,
    # so if that's not set then these applications won't be running.

    reason = """
    `LiveLoad` requires that its own application be started on nodes.

    If the FLAME node has been created with the current release code,
    it should be properly handled and should not be causing an error.
    """

    :ok = ensure_required_app_started!(:live_load, reason)

    reason = """
    `LiveLoad` uses the `:amoc` application in order to manage the load test
    lifecycle in a distributed fashion. `:amoc` powers the core of `LiveLoad`'s
    application.

    `:amoc` is included in LiveLoad's mix.exs as part of the `:included_applications`
    list, so if the FLAME node has been created with the current release code,
    it should be properly handled and should not be causing an error.
    """

    :ok = ensure_required_app_started!(:amoc, reason)

    reason = """
    `LiveLoad.Cluster` uses the `:os_mon` application in order to calculate
    the correct number of nodes for the load test to run. This calculation
    is done by checking the details of the FLAME node, including checking
    the available disk space, memory, CPUs, and schedulers available.

    `:os_mon` is included in LiveLoad's mix.exs as part of the `:extra_applications`
    list, so if the FLAME node has been created with the current release code,
    it should be properly handled and should not be causing an error.
    """

    :ok = ensure_required_app_started!(:os_mon, reason)

    # TODO: I need to get the actual limits of the current node.
    # This is sort of a "best-effort get the available resources for the node" situation.
    # It doesn't account for Kubernetes and containerization and stuff... I haven't dealt with that
    # in a really long time and I don't remember all of the /proc stuff that I need to read to get the details.
    # For now this is good enough. LiveLoad probably shouldn't be run on a node that can have other stuff on it
    # anyways, so in theory it should assume that it has control of the entire node.
    memory_data = :memsup.get_system_memory_data()

    %__MODULE__{
      node: node(),
      ref: make_ref(),
      schedulers_online: System.schedulers_online(),
      logical_processors: system_info_or_nil(:logical_processors),
      logical_processors_online: system_info_or_nil(:logical_processors_online),
      logical_processors_available: system_info_or_nil(:logical_processors_available),
      total_memory: Keyword.fetch!(memory_data, :total_memory),
      available_memory:
        Keyword.get_lazy(memory_data, :available_memory, fn ->
          Keyword.fetch!(memory_data, :cached_memory) + Keyword.fetch!(memory_data, :buffered_memory) +
            Keyword.fetch!(memory_data, :free_memory)
        end)
    }
  end

  defp ensure_required_app_started!(app_name, app_reason) do
    case Application.ensure_all_started(app_name) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise RuntimeError, """
        The `:#{app_name}` application could not be started on the FLAME node!

        #{app_reason}

        If you are hitting this error, it means that either you are starting a separate
        release from the one that LiveLoad was built with, or the FLAME backend you are
        using is not properly handling syncing the applications to the FLAME node.

        If the release that you are starting is the same, and the FLAME backend is properly
        handling syncing the applications to the FLAME node, then this may be a critical issue
        in `LiveLoad` itself and should be reported to the maintainers.

        Please file issues at: https://github.com/probably-not/live-load/issues.

        The following error was received when ensuring that `:#{app_name}` is started:

        #{inspect(reason)}
        """
    end
  end

  @compile {:inline, system_info_or_nil: 1}
  defp system_info_or_nil(key) do
    case :erlang.system_info(key) do
      :unknown -> nil
      value -> value
    end
  end

  def seed_amoc_cluster(%__MODULE__{} = cluster_node, cluster_nodes, master_node, timeout) do
    ref = make_ref()
    reply_to = self()
    send(cluster_node.tracked_pid, {:seed_amoc_cluster, cluster_node.ref, ref, cluster_nodes, master_node, reply_to})

    monitor_ref = Process.monitor(cluster_node.tracked_pid)

    receive do
      {:seed_amoc_cluster_done, ^ref, results} ->
        Process.demonitor(monitor_ref, [:flush])
        results

      {:DOWN, ^monitor_ref, _, _, reason} ->
        {:error, reason}
    after
      timeout -> {:error, :timeout}
    end
  end

  defimpl FLAME.Trackable do
    def track(%LiveLoad.Cluster.Node{ref: ref} = data, acc, node) do
      parent = self()

      {pid, monitor_ref} =
        Node.spawn_monitor(node, fn ->
          send(parent, {ref, :started})
          loop(ref)
        end)

      receive do
        {^ref, :started} ->
          Process.demonitor(monitor_ref, [:flush])
          {%{data | tracked_pid: pid}, [pid | acc]}

        {:DOWN, ^monitor_ref, _, _, reason} ->
          exit(reason)
      end
    end

    defp loop(ref) do
      receive do
        {:seed_amoc_cluster, ^ref, request_ref, cluster_nodes, master_node, reply_to} ->
          results = LiveLoad.Cluster.AmocSeed.seed_amoc_cluster_on_node(cluster_nodes, master_node)
          send(reply_to, {:seed_amoc_cluster_done, request_ref, results})
          loop(ref)

        {^ref, :stop} ->
          :ok
      end
    end
  end
end
