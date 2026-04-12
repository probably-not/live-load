defmodule LiveLoad.Scenario.Topology.BrowserStore do
  @moduledoc false

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, :ok}
  end

  @impl true
  def terminate(_reason, state) do
    LiveLoad.Scenario.Topology.clear_browser()
    {:noreply, state}
  end
end
