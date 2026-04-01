defmodule LiveLoad.Telemetry.Listener do
  @moduledoc false
  # `LiveLoad.Telemetry.Listener` is the node-local telemetry handler module running
  # on each of the nodes running the load test. Since LiveLoad runs distributed on all
  # nodes in the node pools available, we need to listen to telemetry and metrics on each
  # node and then forward the telemetry to the controller node.

  use GenServer

  alias LiveLoad.Telemetry.Result

  require Logger

  def start_link({collector_pid, %LiveLoad.Browser{} = browser, error_rate, bucket_width_ms})
      when is_pid(collector_pid) and is_float(error_rate) and error_rate >= 0.0 do
    case GenServer.start_link(__MODULE__, {collector_pid, browser, error_rate, bucket_width_ms}) do
      {:ok, pid} when is_pid(pid) -> {:ok, tap(pid, &install/1)}
      # For right now, the listener doesn't have a name, so I'm not adding a catch
      # for `{:error, {:already_started, pid}}`. Since this runs on each child node
      # for the duration of the load test, I don't think it should be named.
      other -> other
    end
  end

  @default_error_rate 0.02
  @default_bucket_width_ms to_timeout(second: 5)

  def start_link({collector_pid, %LiveLoad.Browser{} = browser, error_rate}) when is_pid(collector_pid) do
    Logger.warning([
      "[LiveLoad.Telemetry.Listener] received invalid error rate: ",
      inspect(error_rate),
      "; defaulting to #{@default_error_rate}"
    ])

    start_link({collector_pid, browser, @default_error_rate, @default_bucket_width_ms})
  end

  def start_link({collector_pid, %LiveLoad.Browser{} = browser}) when is_pid(collector_pid) do
    start_link({collector_pid, browser, @default_error_rate, @default_bucket_width_ms})
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
            browser: LiveLoad.Browser.t(),
            error_rate: float(),
            bucket_width_ms: pos_integer(),
            monotonic_start: integer() | nil,
            start_system_time: integer() | nil,
            started: MapSet.t(:amoc_scenario.user_id()),
            stopped: MapSet.t(:amoc_scenario.user_id()),
            succeeded: non_neg_integer(),
            failed: non_neg_integer(),
            sketches: %{Result.sketch_name() => :ddskerl_std.ddsketch()},
            counters: %{Result.counter_name() => non_neg_integer()},
            sketch_buckets: %{Result.bucket_index() => %{Result.sketch_name() => :ddskerl_std.ddsketch()}},
            counter_buckets: %{Result.bucket_index() => %{Result.counter_name() => non_neg_integer()}}
          }

    defstruct [
      :collector_pid,
      :browser,
      :error_rate,
      :bucket_width_ms,
      :monotonic_start,
      :start_system_time,
      started: MapSet.new(),
      stopped: MapSet.new(),
      succeeded: 0,
      failed: 0,
      sketches: %{},
      counters: %{},
      sketch_buckets: %{},
      counter_buckets: %{}
    ]

    def new(collector_pid, browser, error_rate, bucket_width_ms) do
      %__MODULE__{
        collector_pid: collector_pid,
        browser: browser,
        error_rate: error_rate,
        bucket_width_ms: bucket_width_ms
      }
    end
  end

  @impl true
  def init({collector_pid, browser, error_rate, bucket_width_ms}) do
    {:ok, State.new(collector_pid, browser, error_rate, bucket_width_ms), {:continue, :initialize_metrics}}
  end

  @impl true
  def handle_continue(:initialize_metrics, %State{} = state) do
    sketch_opts = %{error: state.error_rate}
    sketches = Map.new(Result.sketch_names(), &{&1, :ddskerl_std.new(sketch_opts)})
    counters = Map.new(Result.counter_names(), &{&1, 0})
    {:noreply, %{state | sketches: sketches, counters: counters}}
  end

  @impl true
  def handle_info(:node_complete, %State{} = state) do
    all_buckets =
      MapSet.union(
        MapSet.new(Map.keys(state.sketch_buckets)),
        MapSet.new(Map.keys(state.counter_buckets))
      )

    time_series =
      Map.new(all_buckets, fn bucket ->
        {bucket,
         %{
           sketches: Map.get(state.sketch_buckets, bucket, %{}),
           counters: Map.get(state.counter_buckets, bucket, %{})
         }}
      end)

    stats = %Result{
      total: MapSet.size(state.stopped),
      succeeded: state.succeeded,
      failed: state.failed,
      sketches: state.sketches,
      counters: state.counters,
      bucket_width_ms: state.bucket_width_ms,
      start_system_time: state.start_system_time,
      time_series: time_series
    }

    :ok = LiveLoad.Telemetry.Collector.node_complete(state.collector_pid, stats)

    {:noreply, state}
  end

  @impl true
  def handle_cast(:stop, %State{} = state) do
    {:stop, :normal, state}
  end

  ###################################
  ## AMoC Scenario Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :start], %{system_time: system_time, monotonic_time: monotonic_time},
         %{user_id: user_id}},
        %State{monotonic_start: nil} = state
      ) do
    state = %{
      state
      | started: MapSet.put(state.started, user_id),
        monotonic_start: monotonic_time,
        start_system_time: system_time
    }

    bucket = bucket(state, monotonic_time)
    counters = increment_counter(state.counters, :scenario_users_started)
    counter_buckets = increment_counter_bucket(state.counter_buckets, bucket, :scenario_users_started)

    {:noreply, %{state | counters: counters, counter_buckets: counter_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :start], %{monotonic_time: monotonic_time}, %{user_id: user_id}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)
    counters = increment_counter(state.counters, :scenario_users_started)
    counter_buckets = increment_counter_bucket(state.counter_buckets, bucket, :scenario_users_started)

    {:noreply,
     %{state | started: MapSet.put(state.started, user_id), counters: counters, counter_buckets: counter_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :stop], %{duration: duration, monotonic_time: monotonic_time},
         %{user_id: user_id}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    sketches = maybe_insert_to_sketch(state.sketches, :scenario_duration_us, duration_us, state.error_rate)
    bucket = bucket(state, monotonic_time)

    sketch_buckets =
      maybe_insert_to_sketch_bucket(state.sketch_buckets, bucket, :scenario_duration_us, duration_us, state.error_rate)

    counters = increment_counter(state.counters, :scenario_users_completed)
    counter_buckets = increment_counter_bucket(state.counter_buckets, bucket, :scenario_users_completed)

    state = %{
      state
      | stopped: MapSet.put(state.stopped, user_id),
        succeeded: state.succeeded + 1,
        sketches: sketches,
        sketch_buckets: sketch_buckets,
        counters: counters,
        counter_buckets: counter_buckets
    }

    {:noreply, tap(state, &maybe_send_completion/1)}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:amoc, :scenario, :start, :exception], %{duration: duration, monotonic_time: monotonic_time},
         %{user_id: user_id}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    sketches = maybe_insert_to_sketch(state.sketches, :scenario_duration_us, duration_us, state.error_rate)
    bucket = bucket(state, monotonic_time)

    sketch_buckets =
      maybe_insert_to_sketch_bucket(state.sketch_buckets, bucket, :scenario_duration_us, duration_us, state.error_rate)

    counters = increment_counter(state.counters, :scenario_users_completed)
    counter_buckets = increment_counter_bucket(state.counter_buckets, bucket, :scenario_users_completed)

    state = %{
      state
      | stopped: MapSet.put(state.stopped, user_id),
        failed: state.failed + 1,
        sketches: sketches,
        sketch_buckets: sketch_buckets,
        counters: counters,
        counter_buckets: counter_buckets
    }

    {:noreply, tap(state, &maybe_send_completion/1)}
  end

  ###################################
  ## LiveView Connection Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :connected], %{duration: duration, monotonic_time: monotonic_time},
         %{href: href}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    bucket = bucket(state, monotonic_time)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_connection_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_connection_duration_us, href}, duration_us, state.error_rate)

    sketch_buckets =
      state.sketch_buckets
      |> maybe_insert_to_sketch_bucket(bucket, :liveview_connection_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch_bucket(bucket, {:liveview_connection_duration_us, href}, duration_us, state.error_rate)

    {:noreply, %{state | sketches: sketches, sketch_buckets: sketch_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :disconnected], %{monotonic_time: monotonic_time}, %{href: href}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)

    counters =
      state.counters
      |> increment_counter(:liveview_disconnections)
      |> increment_counter({:liveview_disconnections, href})

    counter_buckets =
      state.counter_buckets
      |> increment_counter_bucket(bucket, :liveview_disconnections)
      |> increment_counter_bucket(bucket, {:liveview_disconnections, href})

    {:noreply, %{state | counters: counters, counter_buckets: counter_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :reconnected], %{duration: duration, monotonic_time: monotonic_time},
         %{href: href}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    bucket = bucket(state, monotonic_time)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_reconnection_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_reconnection_duration_us, href}, duration_us, state.error_rate)

    sketch_buckets =
      state.sketch_buckets
      |> maybe_insert_to_sketch_bucket(bucket, :liveview_reconnection_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch_bucket(bucket, {:liveview_reconnection_duration_us, href}, duration_us, state.error_rate)

    counters =
      state.counters
      |> increment_counter(:liveview_reconnections)
      |> increment_counter({:liveview_reconnections, href})

    counter_buckets =
      state.counter_buckets
      |> increment_counter_bucket(bucket, :liveview_reconnections)
      |> increment_counter_bucket(bucket, {:liveview_reconnections, href})

    {:noreply,
     %{state | sketches: sketches, sketch_buckets: sketch_buckets, counters: counters, counter_buckets: counter_buckets}}
  end

  ###################################
  ## LiveView Navigation Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :page_loading, :stop], %{duration: duration, monotonic_time: monotonic_time},
         %{kind: kind}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    bucket = bucket(state, monotonic_time)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_page_loading_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_page_loading_duration_us, kind}, duration_us, state.error_rate)

    sketch_buckets =
      state.sketch_buckets
      |> maybe_insert_to_sketch_bucket(bucket, :liveview_page_loading_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch_bucket(bucket, {:liveview_page_loading_duration_us, kind}, duration_us, state.error_rate)

    {:noreply, %{state | sketches: sketches, sketch_buckets: sketch_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :page_loading, :exception],
         %{duration: duration, monotonic_time: monotonic_time}, %{kind: kind}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    bucket = bucket(state, monotonic_time)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_page_loading_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_page_loading_duration_us, kind}, duration_us, state.error_rate)

    sketch_buckets =
      state.sketch_buckets
      |> maybe_insert_to_sketch_bucket(bucket, :liveview_page_loading_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch_bucket(bucket, {:liveview_page_loading_duration_us, kind}, duration_us, state.error_rate)

    counters =
      state.counters
      |> increment_counter(:liveview_canceled_loads)
      |> increment_counter({:liveview_canceled_loads, kind})

    counter_buckets =
      state.counter_buckets
      |> increment_counter_bucket(bucket, :liveview_canceled_loads)
      |> increment_counter_bucket(bucket, {:liveview_canceled_loads, kind})

    {:noreply,
     %{state | sketches: sketches, sketch_buckets: sketch_buckets, counters: counters, counter_buckets: counter_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :navigate], %{monotonic_time: monotonic_time}, %{type: type}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)

    counters =
      state.counters
      |> increment_counter(:liveview_navigations)
      |> increment_counter({:liveview_navigations, type})

    counter_buckets =
      state.counter_buckets
      |> increment_counter_bucket(bucket, :liveview_navigations)
      |> increment_counter_bucket(bucket, {:liveview_navigations, type})

    {:noreply, %{state | counters: counters, counter_buckets: counter_buckets}}
  end

  ###################################
  ## LiveView Interaction Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :liveview, :loading_class, :stop],
         %{duration: duration, monotonic_time: monotonic_time}, %{class: class}},
        %State{} = state
      ) do
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    bucket = bucket(state, monotonic_time)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:liveview_loading_class_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch({:liveview_loading_class_duration_us, class}, duration_us, state.error_rate)

    sketch_buckets =
      state.sketch_buckets
      |> maybe_insert_to_sketch_bucket(bucket, :liveview_loading_class_duration_us, duration_us, state.error_rate)
      |> maybe_insert_to_sketch_bucket(
        bucket,
        {:liveview_loading_class_duration_us, class},
        duration_us,
        state.error_rate
      )

    {:noreply, %{state | sketches: sketches, sketch_buckets: sketch_buckets}}
  end

  ###################################
  ## HTTP Telemetry
  ###################################

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :http, :request, :stop], %{monotonic_time: monotonic_time} = measurements,
         %{resource_type: resource_type}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)

    {sketches, sketch_buckets} =
      Enum.reduce(
        [
          http_request_duration_us: :duration,
          http_request_ttfb_us: :ttfb,
          http_request_dns_us: :dns,
          http_request_connect_us: :connect,
          http_request_tls_us: :tls
        ],
        {state.sketches, state.sketch_buckets},
        fn {name, measurement}, {sketches, sketch_buckets} ->
          value = Map.get(measurements, measurement, -1)
          value_us = System.convert_time_unit(value, :native, :microsecond)

          sketches =
            sketches
            |> maybe_insert_to_sketch(name, value_us, state.error_rate)
            |> maybe_insert_to_sketch({name, resource_type}, value_us, state.error_rate)

          sketch_buckets =
            sketch_buckets
            |> maybe_insert_to_sketch_bucket(bucket, name, value_us, state.error_rate)
            |> maybe_insert_to_sketch_bucket(bucket, {name, resource_type}, value_us, state.error_rate)

          {sketches, sketch_buckets}
        end
      )

    {:noreply, %{state | sketches: sketches, sketch_buckets: sketch_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :websocket, :opened], %{monotonic_time: monotonic_time}, %{url: url}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)
    cleaned_url = clean_url(url)

    counters =
      state.counters
      |> increment_counter(:websocket_connections_opened)
      |> increment_counter({:websocket_connections_opened, cleaned_url})

    counter_buckets =
      state.counter_buckets
      |> increment_counter_bucket(bucket, :websocket_connections_opened)
      |> increment_counter_bucket(bucket, {:websocket_connections_opened, cleaned_url})

    {:noreply, %{state | counters: counters, counter_buckets: counter_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :websocket, :closed], %{monotonic_time: monotonic_time}, %{url: url}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)
    cleaned_url = clean_url(url)

    counters =
      state.counters
      |> increment_counter(:websocket_connections_closed)
      |> increment_counter({:websocket_connections_closed, cleaned_url})

    counter_buckets =
      state.counter_buckets
      |> increment_counter_bucket(bucket, :websocket_connections_closed)
      |> increment_counter_bucket(bucket, {:websocket_connections_closed, cleaned_url})

    {:noreply, %{state | counters: counters, counter_buckets: counter_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :websocket, :frame_sent], %{payload_size: size, monotonic_time: monotonic_time},
         %{url: url}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)
    cleaned_url = clean_url(url)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:websocket_frame_sent_bytes, size, state.error_rate)
      |> maybe_insert_to_sketch({:websocket_frame_sent_bytes, cleaned_url}, size, state.error_rate)

    sketch_buckets =
      state.sketch_buckets
      |> maybe_insert_to_sketch_bucket(bucket, :websocket_frame_sent_bytes, size, state.error_rate)
      |> maybe_insert_to_sketch_bucket(bucket, {:websocket_frame_sent_bytes, cleaned_url}, size, state.error_rate)

    {:noreply, %{state | sketches: sketches, sketch_buckets: sketch_buckets}}
  end

  @impl true
  def handle_cast(
        {:telemetry, [:live_load, :websocket, :frame_received], %{payload_size: size, monotonic_time: monotonic_time},
         %{url: url}},
        %State{} = state
      ) do
    bucket = bucket(state, monotonic_time)
    cleaned_url = clean_url(url)

    sketches =
      state.sketches
      |> maybe_insert_to_sketch(:websocket_frame_received_bytes, size, state.error_rate)
      |> maybe_insert_to_sketch({:websocket_frame_received_bytes, cleaned_url}, size, state.error_rate)

    sketch_buckets =
      state.sketch_buckets
      |> maybe_insert_to_sketch_bucket(bucket, :websocket_frame_received_bytes, size, state.error_rate)
      |> maybe_insert_to_sketch_bucket(bucket, {:websocket_frame_received_bytes, cleaned_url}, size, state.error_rate)

    {:noreply, %{state | sketches: sketches, sketch_buckets: sketch_buckets}}
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

  defp maybe_insert_to_sketch_bucket(buckets, bucket, name, value, error_rate) do
    buckets
    |> Map.put_new(bucket, %{})
    |> Map.update!(bucket, &maybe_insert_to_sketch(&1, name, value, error_rate))
  end

  defp increment_counter(counters, name) do
    Map.update(counters, name, 1, &(&1 + 1))
  end

  defp increment_counter_bucket(buckets, bucket, name) do
    buckets
    |> Map.put_new(bucket, %{})
    |> Map.update!(bucket, &increment_counter(&1, name))
  end

  defp clean_url(url) do
    case URI.new(url) do
      {:ok, %URI{} = uri} ->
        URI.to_string(%{uri | query: nil, fragment: nil})

      {:error, reason} ->
        Logger.warning([
          "[LiveLoad.Telemetry.Listener] Unable to parse URL, falling back to raw URL:",
          " ",
          inspect(url),
          "; ",
          Exception.format_exit(reason)
        ])

        url
    end
  end

  defp bucket(state, monotonic_time)

  defp bucket(%State{monotonic_start: nil}, _monotonic_time) do
    0
  end

  defp bucket(%State{monotonic_start: start, bucket_width_ms: width}, monotonic_time) do
    elapsed_ms = System.convert_time_unit(monotonic_time - start, :native, :millisecond)
    div(elapsed_ms, width)
  end

  defp maybe_send_completion(%State{} = state) do
    if MapSet.size(state.started) > 0 and MapSet.equal?(state.started, state.stopped) do
      :ok = LiveLoad.Browser.drain_metrics(state.browser)
      send(self(), :node_complete)
    end
  end
end
