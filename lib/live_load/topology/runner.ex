defmodule LiveLoad.Topology.Runner do
  @moduledoc false

  use GenServer

  def setup!(server, runner_node, browser_connection_adapter, browser_connection_opts, collector_pid) do
    GenServer.call(server, {:setup, runner_node, browser_connection_adapter, browser_connection_opts, collector_pid})
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    {:ok, []}
  end

  @impl true
  def handle_call({:setup, runner_node, browser_connection_adapter, browser_connection_opts, collector_pid}, _from, links) do
    # Assertive, but I should probably do error handling at some point...
    {:ok, pid} =
      :rpc.block_call(
        runner_node,
        LiveLoad.Scenario.Topology,
        :setup,
        [{browser_connection_adapter, browser_connection_opts, collector_pid}]
      )

    # Link the topology from the runner node to the current topology. If we go down or lose connection, everything should come down.
    Process.link(pid)
    {:reply, :ok, [pid | links]}
  end
end
