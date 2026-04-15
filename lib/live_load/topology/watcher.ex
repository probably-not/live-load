defmodule LiveLoad.Topology.Watcher do
  @moduledoc false

  use GenServer

  def start_link(caller_pid) when is_pid(caller_pid) do
    GenServer.start_link(__MODULE__, caller_pid)
  end

  @impl true
  def init(caller_pid) do
    # We link to the calling process so that if the calling process has any issues and exits, we close out the resources.
    # This should probably be passed in as an option somewhere instead of forcing the link.
    true = Process.link(caller_pid)
    {:ok, caller_pid}
  end
end
