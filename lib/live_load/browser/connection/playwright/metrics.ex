defmodule LiveLoad.Browser.Connection.Playwright.Metrics do
  @moduledoc false
  # `LiveLoad.Browser.Connection.Playwright.Metrics` is a simple event listener
  # and telemetry router that subscribes to the underlying `PlaywrightEx`
  # browser instance under the `LiveLoad.Browser.Connection.Playwright`
  # implementation in order to listen for metrics coming from the browser.

  use GenServer

  def start_link(connection) do
    GenServer.start_link(__MODULE__, connection)
  end

  def watch_page(server, guid, timeout \\ 10_000) do
    GenServer.call(server, {:watch_page, guid, timeout})
  end

  def drain(server) do
    GenServer.call(server, :drain)
  end

  defmodule State do
    @moduledoc false

    @type t() :: %__MODULE__{
            connection: GenServer.name(),
            subscribed_websockets: %{String.t() => String.t()},
            subscribed_requests: %{String.t() => String.t()}
          }

    defstruct [:connection, subscribed_websockets: %{}, subscribed_requests: %{}]

    def new(connection) do
      %__MODULE__{connection: connection}
    end
  end

  @impl true
  def init(connection) do
    {:ok, State.new(connection)}
  end

  @impl true
  def handle_call({:watch_page, guid, timeout}, _from, %State{} = state) do
    :ok = PlaywrightEx.subscribe(guid, connection: state.connection)

    Enum.each([:console, :request, :response, :requestFinished, :requestFailed], fn event ->
      {:ok, _} =
        PlaywrightEx.Page.update_subscription(guid,
          event: event,
          enabled: true,
          timeout: timeout,
          connection: state.connection
        )
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:drain, _from, %State{} = state) do
    {:reply, :ok, state}
  end

  ###################################
  ## Request related subscriptions
  ###################################

  @impl true
  def handle_info({:playwright_msg, %{method: :__create__, params: %{type: "Request"} = params}}, %State{} = state) do
    :ok = PlaywrightEx.subscribe(params.guid, connection: state.connection)

    :telemetry.execute(
      [:live_load, :http, :request, :start],
      %{system_time: System.system_time(), monotonic_time: System.monotonic_time()},
      %{
        url: params.initializer.url,
        resource_type: params.initializer.resource_type,
        method: params.initializer.method,
        is_navigation: params.initializer.is_navigation_request,
        span_id: params.guid
      }
    )

    new = Map.put(state.subscribed_requests, params.guid, params.initializer.resource_type)
    {:noreply, %{state | subscribed_requests: new}}
  end

  @impl true
  def handle_info(
        {:playwright_msg, %{method: :__create__, guid: guid, params: %{type: "Response"} = params}},
        %State{} = state
      )
      when is_map_key(state.subscribed_requests, guid) do
    timing = params.initializer.timing

    {resource_type, left} = Map.pop!(state.subscribed_requests, guid)

    content_length =
      Enum.find_value(params.initializer.headers, fn
        %{name: "content-length", value: value} -> String.to_integer(value)
        _ -> nil
      end)

    :telemetry.execute(
      [:live_load, :http, :request, :stop],
      %{
        monotonic_time: System.monotonic_time(),
        duration: timing_to_native(timing.response_start),
        dns: timing_to_native(timing.domain_lookup_end - timing.domain_lookup_start),
        connect: timing_to_native(timing.connect_end - timing.connect_start),
        tls: timing_to_native(timing.connect_end - timing.secure_connection_start),
        ttfb: timing_to_native(timing.response_start - timing.request_start),
        content_length: content_length
      },
      %{url: params.initializer.url, resource_type: resource_type, status: params.initializer.status, span_id: guid}
    )

    {:noreply, %{state | subscribed_requests: left}}
  end

  ###################################
  ## Websocket related subsriptions
  ###################################

  @impl true
  def handle_info({:playwright_msg, %{method: :__create__, params: %{type: "WebSocket"} = params}}, %State{} = state) do
    :ok = PlaywrightEx.subscribe(params.guid, connection: state.connection)

    :telemetry.execute([:live_load, :websocket, :opened], %{count: 1, monotonic_time: System.monotonic_time()}, %{
      url: params.initializer.url
    })

    new = Map.put(state.subscribed_websockets, params.guid, params.initializer.url)
    {:noreply, %{state | subscribed_websockets: new}}
  end

  @impl true
  def handle_info({:playwright_msg, %{method: :close, guid: guid}}, %State{} = state)
      when is_map_key(state.subscribed_websockets, guid) do
    {url, left} = Map.pop!(state.subscribed_websockets, guid)

    :telemetry.execute([:live_load, :websocket, :closed], %{count: 1, monotonic_time: System.monotonic_time()}, %{
      url: url
    })

    {:noreply, %{state | subscribed_websockets: left}}
  end

  @impl true
  def handle_info(
        {:playwright_msg, %{method: :frame_sent, guid: guid, params: %{data: data, opcode: opcode}}},
        %State{} = state
      )
      when is_map_key(state.subscribed_websockets, guid) do
    :telemetry.execute(
      [:live_load, :websocket, :frame_sent],
      %{payload_size: byte_size(data), monotonic_time: System.monotonic_time()},
      %{url: Map.fetch!(state.subscribed_websockets, guid), opcode: opcode}
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:playwright_msg, %{method: :frame_received, guid: guid, params: %{data: data, opcode: opcode}}},
        %State{} = state
      )
      when is_map_key(state.subscribed_websockets, guid) do
    :telemetry.execute(
      [:live_load, :websocket, :frame_received],
      %{payload_size: byte_size(data), monotonic_time: System.monotonic_time()},
      %{url: Map.fetch!(state.subscribed_websockets, guid), opcode: opcode}
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:playwright_msg, message}, %State{} = state) do
    :telemetry.execute([:live_load, :unknown_playwright_message], %{count: 1, monotonic_time: System.monotonic_time()}, %{
      message: message
    })

    {:noreply, state}
  end

  defp timing_to_native(timing) when timing < 0, do: -1
  defp timing_to_native(timing), do: System.convert_time_unit(round(timing * 1000), :microsecond, :native)
end
