defmodule LiveLoad.Telemetry.Listener do
  @moduledoc false
  # `LiveLoad.Telemetry.Listener` is the node-local telemetry handler module running
  # on each of the nodes running the load test. Since LiveLoad runs distributed on all
  # nodes in the node pools available, we need to listen to telemetry and metrics on each
  # node and then forward the telemetry to the controller node.

  use GenServer

  alias LiveLoad.Result

  require Logger

  def start_link({collector_pid, error_rate}) when is_pid(collector_pid) and is_float(error_rate) and error_rate >= 0.0 do
    case GenServer.start_link(__MODULE__, {collector_pid, error_rate}) do
      {:ok, pid} when is_pid(pid) -> {:ok, tap(pid, &install/1)}
      # For right now, the listener doesn't have a name, so I'm not adding a catch
      # for `{:error, {:already_started, pid}}`. Since this runs on each child node
      # for the duration of the load test, I don't think it should be named.
      other -> other
    end
  end

  @default_error_rate 0.02

  def start_link({collector_pid, error_rate}) when is_pid(collector_pid) do
    Logger.warning([
      "[LiveLoad.Telemetry.Listener] received invalid error rate: ",
      inspect(error_rate),
      "; defaulting to #{@default_error_rate}"
    ])

    start_link({collector_pid, @default_error_rate})
  end

  def start_link(collector_pid) when is_pid(collector_pid) do
    start_link({collector_pid, @default_error_rate})
  end

  def stop(server) do
    if pid = GenServer.whereis(server) do
      ref = Process.monitor(pid)
      GenServer.cast(pid, :stop)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      end
    else
      :ok
    end
  after
    uninstall(server)
  end

  def handle_telemetry(event, measurements, metadata, %{listener: server}) do
    GenServer.cast(server, {:telemetry, event, measurements, metadata})
  end

  defp install(server) do
    handlers = %{
      [:amoc, :scenario, :start, :start] => &__MODULE__.handle_telemetry/4,
      [:amoc, :scenario, :start, :stop] => &__MODULE__.handle_telemetry/4,
      [:amoc, :scenario, :start, :exception] => &__MODULE__.handle_telemetry/4
    }

    Enum.each(handlers, fn {event, handler} ->
      :telemetry.attach({__MODULE__, server, event}, event, handler, %{listener: server})
    end)
  end

  defp uninstall(server) do
    events = [
      [:amoc, :scenario, :start, :start],
      [:amoc, :scenario, :start, :stop],
      [:amoc, :scenario, :start, :exception]
    ]

    Enum.each(events, fn event ->
      :telemetry.detach({__MODULE__, server, event})
    end)
  end

  defmodule State do
    @moduledoc false

    @type t() :: %__MODULE__{
            collector_pid: pid(),
            started: MapSet.t(:amoc_scenario.user_id()),
            stopped: MapSet.t(:amoc_scenario.user_id()),
            succeeded: non_neg_integer(),
            failed: non_neg_integer(),
            sketches: %{Result.sketch_name() => :ddskerl_std.ddsketch()},
            counters: %{Result.counter_name() => non_neg_integer()}
          }

    defstruct [
      :collector_pid,
      started: MapSet.new(),
      stopped: MapSet.new(),
      succeeded: 0,
      failed: 0,
      sketches: %{},
      counters: %{}
    ]

    def new(collector_pid) do
      %__MODULE__{collector_pid: collector_pid}
    end
  end

  @impl true
  def init({collector_pid, error_rate}) do
    {:ok, State.new(collector_pid), {:continue, {:initialize_metrics, error_rate}}}
  end

  @impl true
  def handle_continue({:initialize_metrics, error_rate}, %State{} = state) do
    sketch_opts = %{error: error_rate}
    sketches = Map.new(Result.sketch_names(), &{&1, :ddskerl_std.new(sketch_opts)})
    counters = Map.new(Result.counter_names(), &{&1, 0})
    {:noreply, %{state | sketches: sketches, counters: counters}}
  end

  @impl true
  def handle_cast(:stop, %State{} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:telemetry, [:amoc, :scenario, :start, :start], _measurements, %{user_id: user_id}}, %State{} = state) do
    {:noreply, %{state | started: MapSet.put(state.started, user_id)}}
  end

  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :stop], %{duration: duration}, %{user_id: user_id}},
        %State{} = state
      ) do
    state = %{
      state
      | stopped: MapSet.put(state.stopped, user_id),
        succeeded: state.succeeded + 1,
        sketches:
          Map.update!(
            state.sketches,
            :scenario_duration_us,
            fn sketch ->
              :ddskerl_std.insert(sketch, System.convert_time_unit(duration, :native, :microsecond))
            end
          )
    }

    {:noreply, tap(state, &maybe_send_completion/1)}
  end

  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :exception], %{duration: duration}, %{user_id: user_id}},
        %State{} = state
      ) do
    state = %{
      state
      | stopped: MapSet.put(state.stopped, user_id),
        failed: state.failed + 1,
        sketches:
          Map.update!(
            state.sketches,
            :scenario_duration_us,
            fn sketch ->
              :ddskerl_std.insert(sketch, System.convert_time_unit(duration, :native, :microsecond))
            end
          )
    }

    {:noreply, tap(state, &maybe_send_completion/1)}
  end

  @impl true
  def handle_cast({:telemetry, event, measurements, metadata}, %State{} = state) do
    Logger.warning([
      "[LiveLoad.Telemetry.Listener] Unhandled telemetry event received:",
      " ",
      inspect(event),
      "; ",
      inspect(measurements),
      "; ",
      inspect(metadata)
    ])

    {:noreply, state}
  end

  defp maybe_send_completion(%State{} = state) do
    if MapSet.size(state.started) > 0 and MapSet.equal?(state.started, state.stopped) do
      stats = %Result{
        total: MapSet.size(state.stopped),
        succeeded: state.succeeded,
        failed: state.failed,
        sketches: state.sketches,
        counters: state.counters
      }

      :ok = LiveLoad.Telemetry.Collector.node_complete(state.collector_pid, stats)
    end
  end
end
