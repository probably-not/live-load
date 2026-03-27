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
    Enum.each(events(), fn event ->
      :telemetry.attach({__MODULE__, server, event}, event, &__MODULE__.handle_telemetry/4, %{listener: server})
    end)
  end

  defp uninstall(server) do
    Enum.each(events(), fn event ->
      :telemetry.detach({__MODULE__, server, event})
    end)
  end

  defp events do
    [
      [:amoc, :scenario, :start, :start],
      [:amoc, :scenario, :start, :stop],
      [:amoc, :scenario, :start, :exception],
      [:live_load, :liveview, :connected],
      [:live_load, :liveview, :disconnected],
      [:live_load, :liveview, :reconnected],
      [:live_load, :liveview, :page_loading, :stop],
      [:live_load, :liveview, :page_loading, :exception],
      [:live_load, :liveview, :loading_class, :stop],
      [:live_load, :liveview, :navigate],
      [:live_load, :http, :request, :stop],
      [:live_load, :websocket, :opened],
      [:live_load, :websocket, :closed],
      [:live_load, :websocket, :frame_sent],
      [:live_load, :websocket, :frame_received]
    ]
  end

  defmodule State do
    @moduledoc false

    @type t() :: %__MODULE__{
            collector_pid: pid(),
            error_rate: float(),
            started: MapSet.t(:amoc_scenario.user_id()),
            stopped: MapSet.t(:amoc_scenario.user_id()),
            succeeded: non_neg_integer(),
            failed: non_neg_integer(),
            sketches: %{Result.sketch_name() => :ddskerl_std.ddsketch()},
            counters: %{Result.counter_name() => non_neg_integer()}
          }

    defstruct [
      :collector_pid,
      :error_rate,
      started: MapSet.new(),
      stopped: MapSet.new(),
      succeeded: 0,
      failed: 0,
      sketches: %{},
      counters: %{}
    ]

    def new(collector_pid, error_rate) do
      %__MODULE__{collector_pid: collector_pid, error_rate: error_rate}
    end
  end

  @impl true
  def init({collector_pid, error_rate}) do
    {:ok, State.new(collector_pid, error_rate), {:continue, :initialize_metrics}}
  end

  @impl true
  def handle_continue(:initialize_metrics, %State{} = state) do
    sketch_opts = %{error: state.error_rate}
    sketches = Map.new(Result.sketch_names(), &{&1, :ddskerl_std.new(sketch_opts)})
    counters = Map.new(Result.counter_names(), &{&1, 0})
    {:noreply, %{state | sketches: sketches, counters: counters}}
  end

  @impl true
  def handle_cast(:stop, %State{} = state) do
    {:stop, :normal, state}
  end

  ###################################
  ## AMoC Scenario Telemetry
  ###################################

  @impl true
  def handle_cast({:telemetry, [:amoc, :scenario, :start, :start], _measurements, %{user_id: user_id}}, %State{} = state) do
    {:noreply, %{state | started: MapSet.put(state.started, user_id)}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :stop], %{duration: duration}, %{user_id: user_id}},
        %State{} = state
      ) do
    state = %{
      state
      | stopped: MapSet.put(state.stopped, user_id),
        succeeded: state.succeeded + 1,
        sketches:
          maybe_insert_to_sketch(
            state.sketches,
            :scenario_duration_us,
            System.convert_time_unit(duration, :native, :microsecond),
            state.error_rate
          )
    }

    {:noreply, tap(state, &maybe_send_completion/1)}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :exception], %{duration: duration}, %{user_id: user_id}},
        %State{} = state
      ) do
    state = %{
      state
      | stopped: MapSet.put(state.stopped, user_id),
        failed: state.failed + 1,
        sketches:
          maybe_insert_to_sketch(
            state.sketches,
            :scenario_duration_us,
            System.convert_time_unit(duration, :native, :microsecond),
            state.error_rate
          )
    }

    {:noreply, tap(state, &maybe_send_completion/1)}
  end

  ###################################
  ## LiveView Connection Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :connected], %{duration: duration}, %{href: href}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_connection_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_connection_duration_us, href}, duration_us, state.error_rate)

    {:noreply, %{state | sketches: sketches}}
  end

  @impl true
  def handle_cast({:telemetry, [:live_load, :liveview, :disconnected], _measurements, %{href: href}}, %State{} = state) do
    counters =
      state.counters
      |> increment_counter(:liveview_disconnections)
      |> increment_counter({:liveview_disconnections, href})

    {:noreply, %{state | counters: counters}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :reconnected], %{duration: duration}, %{href: href}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_reconnection_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_reconnection_duration_us, href}, duration_us, state.error_rate)

    counters =
      state.counters
      |> increment_counter(:liveview_reconnections)
      |> increment_counter({:liveview_reconnections, href})

    {:noreply, %{state | sketches: sketches, counters: counters}}
  end

  ###################################
  ## LiveView Navigation Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :page_loading, :stop], %{duration: duration}, %{kind: kind}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_page_loading_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_page_loading_duration_us, kind}, duration_us, state.error_rate)

    {:noreply, %{state | sketches: sketches}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :page_loading, :exception], %{duration: duration}, %{kind: kind}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_page_loading_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_page_loading_duration_us, kind}, duration_us, state.error_rate)

    counters =
      state.counters
      |> increment_counter(:liveview_canceled_loads)
      |> increment_counter({:liveview_canceled_loads, kind})

    {:noreply, %{state | sketches: sketches, counters: counters}}
  end

  @impl true
  def handle_cast({:telemetry, [:live_load, :liveview, :navigate], _measurements, %{type: type}}, %State{} = state) do
    counters =
      state.counters
      |> increment_counter(:liveview_navigations)
      |> increment_counter({:liveview_navigations, type})

    {:noreply, %{state | counters: counters}}
  end

  ###################################
  ## LiveView Interaction Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :loading_class, :stop], %{duration: duration}, %{class: class}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_loading_class_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_loading_class_duration_us, class}, duration_us, state.error_rate)

    {:noreply, %{state | sketches: sketches}}
  end

  ###################################
  ## HTTP Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :http, :request, :stop], measurements, %{resource_type: resource_type}},
        %State{} = state
      ) do
    sketches =
      Enum.reduce(
        [
          http_request_duration_us: :duration,
          http_request_ttfb_us: :ttfb,
          http_request_dns_us: :dns,
          http_request_connect_us: :connect,
          http_request_tls_us: :tls
        ],
        state.sketches,
        fn {name, measurement}, sketches ->
          value = Map.get(measurements, measurement, -1)
          value_us = System.convert_time_unit(value, :native, :microsecond)

          sketches
          |> maybe_insert_to_sketch(name, value_us, state.error_rate)
          |> maybe_insert_to_sketch({name, resource_type}, value_us, state.error_rate)
        end
      )

    {:noreply, %{state | sketches: sketches}}
  end

  @impl true
  def handle_cast({:telemetry, [:live_load, :websocket, :opened], _measurements, %{url: url}}, %State{} = state) do
    counters =
      state.counters
      |> increment_counter(:websocket_connections_opened)
      |> increment_counter({:websocket_connections_opened, url})

    {:noreply, %{state | counters: counters}}
  end

  @impl true
  def handle_cast({:telemetry, [:live_load, :websocket, :closed], _measurements, %{url: url}}, %State{} = state) do
    counters =
      state.counters
      |> increment_counter(:websocket_connections_closed)
      |> increment_counter({:websocket_connections_closed, url})

    {:noreply, %{state | counters: counters}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :websocket, :frame_sent], %{payload_size: size}, %{url: url}},
        %State{} = state
      ) do
    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:websocket_frame_sent_bytes, size, state.error_rate)
      |> maybe_insert_to_sketch({:websocket_frame_sent_bytes, url}, size, state.error_rate)

    {:noreply, %{state | sketches: sketches}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :websocket, :frame_received], %{payload_size: size}, %{url: url}},
        %State{} = state
      ) do
    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:websocket_frame_received_bytes, size, state.error_rate)
      |> maybe_insert_to_sketch({:websocket_frame_received_bytes, url}, size, state.error_rate)

    {:noreply, %{state | sketches: sketches}}
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

  defp maybe_insert_to_sketch(sketches, name, value, error_rate) when is_number(value) and value >= 0 do
    sketches
    |> Map.put_new_lazy(name, fn ->
      :ddskerl_std.new(%{error: error_rate})
    end)
    |> Map.update!(name, &:ddskerl_std.insert(&1, value))
  end

  defp maybe_insert_to_sketch(sketches, _name, _value, _error_rate) do
    sketches
  end

  defp increment_counter(counters, name) do
    Map.update(counters, name, 1, &(&1 + 1))
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
