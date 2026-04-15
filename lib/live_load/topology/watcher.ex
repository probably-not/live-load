defmodule LiveLoad.Topology.Watcher do
  @moduledoc false

  use GenServer

  def start_link(caller_pid) when is_pid(caller_pid) do
    GenServer.start_link(__MODULE__, caller_pid)
  end

  @impl true
  def init(caller_pid) do
    monitor_ref = Process.monitor(caller_pid)
    {:ok, monitor_ref}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, _, _, _}, monitor_ref) do
    {:stop, :normal, monitor_ref}
  end
end
