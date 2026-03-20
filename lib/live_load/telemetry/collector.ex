defmodule LiveLoad.Telemetry.Collector do
  @moduledoc false
  # `LiveLoad.Telemetry.Collector` runs on the controller node that is running the load test.
  # Each `LiveLoad.Telemetry.Listener` sends its completed report of telemetry received on the node
  # to the `LiveLoad.Telemetry.Collector`, which merges all of the telemetry data into a single benchmark report.
  # The `LiveLoad.Telemetry.Collector` determines when all nodes have completed running their load test, and
  # signals the controller process that the load test has completed.

  use GenServer

  require Logger

  def start_link(expected_nodes) when is_list(expected_nodes) do
    GenServer.start_link(__MODULE__, expected_nodes)
  end

  def stop(server) do
    GenServer.stop(server)
  end

  def wait_for_completion(server, timeout \\ :infinity) do
    results = GenServer.call(server, :wait_for_completion, timeout)
    {:ok, results}
  catch
    :exit, reason ->
      Logger.warning([
        "[LiveLoad.Telemetry.Collector] exit when waiting for completion:",
        " ",
        Exception.format_exit(reason)
      ])

      {:error, reason}
  end

  def node_complete(server, stats) do
    GenServer.cast(server, {:node_complete, node(), stats})
  end

  defmodule State do
    @moduledoc false
    @type t() :: %__MODULE__{
            expected_nodes: MapSet.t(node()),
            waiters: [GenServer.from()],
            node_stats: %{optional(node()) => %{}}
          }

    defstruct [:expected_nodes, waiters: [], node_stats: %{}]

    def new(expected_nodes) when is_list(expected_nodes) do
      %__MODULE__{expected_nodes: MapSet.new(expected_nodes)}
    end
  end

  @impl true
  def init(expected_nodes) do
    {:ok, State.new(expected_nodes)}
  end

  @impl true
  def handle_call(:wait_for_completion, from, %State{} = state) do
    if map_size(state.node_stats) >= MapSet.size(state.expected_nodes) do
      {:reply, state.node_stats, state}
    else
      {:noreply, %{state | waiters: [from | state.waiters]}}
    end
  end

  @impl true
  def handle_cast({:node_complete, node, stats}, %State{} = state) do
    state = %{state | node_stats: Map.put(state.node_stats, node, stats)}
    {:noreply, tap(state, &maybe_notify_waiters/1)}
  end

  defp maybe_notify_waiters(%State{} = state) do
    if map_size(state.node_stats) >= MapSet.size(state.expected_nodes) do
      Enum.each(state.waiters, &GenServer.reply(&1, state.node_stats))
    end
  end
end
