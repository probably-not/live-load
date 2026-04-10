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

  def stop(server) do
    :gen_statem.stop(server)
  end

  def run_scenario(server, scenario, distributed?, users, opts)

  def run_scenario(server, scenario, false, users, opts) do
    peer = peer(server)
    :rpc.call(peer, :amoc, :do, [scenario, users, opts])
  end

  def run_scenario(server, scenario, true, users, opts) do
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

    args = maybe_add_env_arg(args, init_args[:env])

    controller_pid =
      case :peer.start_link(args) do
        {:error, reason} ->
          raise RuntimeError, "Failed to initialize `:peer` node for `:amoc` to run on: #{inspect(reason)}"

        {:ok, controller_pid} ->
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
    ensure_apps_started(data.peer, [:amoc])
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
    Map.put(args, :env, Enum.map(env, fn {k, v} -> {maybe_charlist(k), maybe_charlist(v)} end))
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
        {:error, _reason} -> started
      end
    end
  end

  defp maybe_charlist(value) when is_list(value), do: value
  defp maybe_charlist(value) when is_binary(value), do: String.to_charlist(value)
end
