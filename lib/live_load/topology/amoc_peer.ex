defmodule LiveLoad.Topology.AmocPeer do
  @moduledoc false

  @behaviour :gen_statem

  defmodule Data do
    @moduledoc false
    @type t() :: %__MODULE__{controller_pid: pid(), peer: node()}
    defstruct [:controller_pid, :peer]
  end

  def start_link(init_args) do
    :gen_statem.start_link(__MODULE__, init_args, [])
  end

  def register_scenarios_to_amoc(server, scenarios) do
    peer = peer(server)

    Enum.reduce_while(scenarios, :ok, fn scenario, :ok ->
      case rpc(peer, :amoc_code_server, :add_module, [scenario]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:add_module_failed, scenario, reason}}}
        {:badrpc, reason} -> {:halt, {:error, {:add_module_rpc_failed, scenario, reason}}}
      end
    end)
  end

  def distribute_scenarios_to_amoc_cluster(server, nodes) do
    peer = peer(server)

    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      do_distribute_scenarios_to_amoc_cluster(peer, node)
    end)
  end

  defp do_distribute_scenarios_to_amoc_cluster(peer, node) do
    with results when is_list(results) <- rpc(peer, :amoc_code_server, :distribute_modules, [node]),
         [] <- Enum.filter(results, fn {_mod, status} -> status != :ok end) do
      {:cont, :ok}
    else
      {:badrpc, reason} ->
        {:halt, {:error, {:distribute_modules_rpc_failed, node, reason}}}

      failures ->
        {:halt, {:error, {:distribute_modules_failed, node, failures}}}
    end
  end

  def stop(server, distributed?)

  def stop(server, true) do
    peer = peer(server)
    :rpc.call(peer, :amoc_dist, :stop, [])
  end

  def stop(server, false) do
    peer = peer(server)
    :rpc.call(peer, :amoc, :stop, [])
  end

  def connect_amoc_cluster(server, nodes) do
    peer = peer(server)
    :ok = :rpc.call(peer, :amoc_cluster, :connect_nodes, [nodes])

    get_status = fn -> :rpc.call(peer, :amoc_cluster, :get_status, []) end

    # This is a brute-force hack since amoc doesn't currently expose a way to ensure that nodes
    # are connected and that all nodes that are expected to be connected are working.
    # amoc connects asynchronously so this just tries to see the status over and over.
    Enum.reduce_while(1..30, {:error, {:waiting_for_cluster, get_status.()}}, fn
      _, {:error, {_, %{to_ack: [], failed_to_connect: []}}} ->
        {:halt, :ok}

      _, {:error, {_, %{to_ack: [], failed_to_connect: [_ | _] = failed}}} ->
        {:halt, {:error, {:failed_to_connect, failed}}}

      _, {:error, {_, %{to_ack: [_ | _]}}} ->
        Process.sleep(to_timeout(second: 1))
        {:cont, {:error, {:waiting_for_cluster, get_status.()}}}
    end)
  end

  def run_scenario(server, scenario, users, opts) do
    peer = peer(server)
    :rpc.call(peer, :amoc, :do, [scenario, users, opts])
  end

  def run_distributed_scenario(server, scenario, users, opts) do
    peer = peer(server)
    :rpc.call(peer, :amoc_dist, :do, [scenario, users, opts])
  end

  def peer(server) do
    :gen_statem.call(server, :peer)
  end

  def child_spec(init_args, child_opts \\ []) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_args]}
    }

    Supervisor.child_spec(default, child_opts)
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(init_args) do
    args = %{
      name: init_args[:node_name] || :peer.random_name(),
      wait_boot: {self(), :peer_ready},
      args: peer_args()
    }

    args = Map.merge(args, peer_name_opts())
    args = maybe_add_env_arg(args, init_args[:env])

    debug? = init_args[:debug] || false

    args =
      if debug? do
        # Standard IO connection will give debug logs on the primary node so that I can see why a node may not be starting up.
        Map.put(args, :connection, :standard_io)
      else
        args
      end

    controller_pid =
      case :peer.start_link(args) do
        {:error, reason} ->
          raise RuntimeError, "Failed to initialize `:peer` node for `:amoc` to run on: #{inspect(reason)}"

        {:ok, controller_pid} ->
          controller_pid

        {:ok, controller_pid, _node} ->
          controller_pid
      end

    peer_timeout = init_args[:peer_timeout] || to_timeout(second: 30)
    {:ok, :waiting_for_peer, %Data{controller_pid: controller_pid}, [{:state_timeout, peer_timeout, :timeout}]}
  end

  def waiting_for_peer(:state_timeout, :timeout, %Data{}) do
    {:stop, :failed_to_initialize_peer_node}
  end

  def waiting_for_peer(:info, {:peer_ready, {:started, peer, pid}}, %Data{controller_pid: pid} = data) do
    {:next_state, :setup_peer, %{data | peer: peer}, [{:next_event, :internal, :setup_peer}]}
  end

  def waiting_for_peer(_event_name, _event_data, _data) do
    {:keep_state_and_data, :postpone}
  end

  def setup_peer(:internal, :setup_peer, %Data{} = data) do
    add_code_paths(data.peer)
    transfer_configuration(data.peer)
    ensure_apps_started(data.peer, [:amoc, :live_load])
    {:next_state, :ready, data}
  end

  def ready({:call, from}, :peer, %Data{} = data) do
    :gen_statem.reply(from, data.peer)
    :keep_state_and_data
  end

  defp maybe_add_env_arg(args, env)

  defp maybe_add_env_arg(args, nil) do
    args
  end

  defp maybe_add_env_arg(args, env) when is_map(env) do
    env =
      env
      |> Map.new(fn {k, v} -> {maybe_charlist(k), maybe_charlist(v)} end)
      |> Map.put_new(~c"ERL_AFLAGS", String.to_charlist(System.get_env("ERL_AFLAGS", "")))
      |> Map.put_new(~c"ERL_ZFLAGS", String.to_charlist(System.get_env("ERL_ZFLAGS", "")))
      |> Map.to_list()

    Map.put(args, :env, env)
  end

  defp peer_args do
    args = [~c"-hidden"]
    args = maybe_add_cookie_args(args)
    in_release? = System.get_env("RELEASE_ROOT") != nil

    if in_release? do
      add_release_boot!(args)
    else
      args
    end
  end

  defp peer_name_opts do
    case Node.self() do
      :nonode@nohost ->
        %{}

      node ->
        host =
          node
          |> Atom.to_string()
          |> String.split("@", parts: 2)
          |> List.last()
          |> String.to_charlist()

        %{host: host, longnames: :net_kernel.longnames()}
    end
  end

  defp maybe_add_cookie_args(args) do
    case Node.get_cookie() do
      :nocookie -> args
      cookie -> [~c"-setcookie", Atom.to_charlist(cookie) | args]
    end
  end

  defp add_release_boot!(args) do
    release_root = System.fetch_env!("RELEASE_ROOT")
    release_vsn = System.fetch_env!("RELEASE_VSN")

    boot_path = Path.join([release_root, "releases", release_vsn, "start_clean"])
    boot_file = boot_path <> ".boot"

    if not File.exists?(boot_file) do
      raise RuntimeError, """
      The current running node was detected to be part of a mix release,
      with the `RELEASE_ROOT` environment variable set to
      #{release_root} and the `RELEASE_VSN` environment
      variable set to #{release_vsn}.

      We tried to load the `start_clean` bootfile from #{boot_file},
      but this file does not exist.
      """
    end

    release_lib = Path.join(release_root, "lib")

    [
      ~c"-boot",
      String.to_charlist(boot_path),
      ~c"-boot_var",
      ~c"RELEASE_LIB",
      String.to_charlist(release_lib)
      | args
    ]
  end

  defp rpc(node, module, function, args) do
    :rpc.block_call(node, module, function, args)
  end

  defp add_code_paths(node) do
    rpc(node, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(node) do
    Enum.each(Application.loaded_applications(), fn {app_name, _, _} ->
      app_name
      |> Application.get_all_env()
      |> Enum.each(fn {key, primary_config} ->
        rpc(node, Application, :put_env, [app_name, key, primary_config, [persistent: true]])
      end)
    end)
  end

  defp ensure_apps_started(node, peer_applications) do
    Enum.reduce(peer_applications, MapSet.new(), fn app, started ->
      maybe_start_app(node, app, started)
    end)
  end

  defp maybe_start_app(node, app, started) do
    if Enum.member?(started, app) do
      started
    else
      case rpc(node, Application, :ensure_all_started, [app]) do
        {:ok, new_apps} -> MapSet.union(started, MapSet.new(new_apps))
        {:error, reason} -> raise RuntimeError, "Unable to start #{app} on amoc_peer node: #{inspect(reason)}"
      end
    end
  end

  defp maybe_charlist(value) when is_list(value), do: value
  defp maybe_charlist(value) when is_binary(value), do: String.to_charlist(value)
end
