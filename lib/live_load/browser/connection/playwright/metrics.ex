defmodule LiveLoad.Browser.Connection.Playwright.Metrics do
  @moduledoc false
  # `LiveLoad.Browser.Connection.Playwright.Metrics` is a simple event listener
  # and telemetry router that subscribes to the events of the pages of the
  # underlying `Playwright` browser instance under the `LiveLoad.Browser.Connection.Playwright`
  # implementation in order to listen for metrics coming from the browser.

  use GenServer

  alias Playwright.Request
  alias Playwright.Response
  alias Playwright.WebSocket

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def watch_page(server, page) do
    GenServer.call(server, {:watch_page, page})
  end

  def drain(server) do
    GenServer.call(server, :drain)
  end

  @impl true
  def init(_opts) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:watch_page, page}, _from, state) do
    Playwright.Page.on(page, :request, &request_started/1)
    Playwright.Page.on(page, :response, &response_received/1)
    Playwright.Page.on(page, :web_socket, &websocket_opened/1)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:drain, _from, state) do
    {:reply, :ok, state}
  end

  ###################################
  ## Request related subscriptions
  ###################################

  defp request_started(request) do
    :telemetry.execute(
      [:live_load, :http, :request, :start],
      %{system_time: System.system_time(), monotonic_time: System.monotonic_time()},
      %{
        url: Request.url(request),
        resource_type: Request.resource_type(request),
        method: Request.method(request),
        is_navigation: Request.is_navigation_request(request),
        span_id: request.guid
      }
    )
  end

  defp response_received(response) do
    request = Response.request(response)
    timing = Request.timing(request)

    content_length =
      case Response.headers(response) do
        %{"content-length" => value} -> String.to_integer(value)
        _ -> nil
      end

    :telemetry.execute(
      [:live_load, :http, :request, :stop],
      %{
        monotonic_time: System.monotonic_time(),
        duration: timing_to_native(timing.responseStart),
        dns: timing_to_native(timing.domainLookupEnd - timing.domainLookupStart),
        connect: timing_to_native(timing.connectEnd - timing.connectStart),
        tls: timing_to_native(timing.connectEnd - timing.secureConnectionStart),
        ttfb: timing_to_native(timing.responseStart - timing.requestStart),
        content_length: content_length
      },
      %{
        url: Response.url(response),
        resource_type: Request.resource_type(request),
        status: Response.status(response),
        span_id: request.guid
      }
    )
  end

  ###################################
  ## Websocket related subsriptions
  ###################################

  defp websocket_opened(websocket) do
    url = WebSocket.url(websocket)

    :telemetry.execute([:live_load, :websocket, :opened], %{count: 1, monotonic_time: System.monotonic_time()}, %{
      url: url
    })

    WebSocket.on(websocket, :frame_sent, &frame(:frame_sent, url, &1))
    WebSocket.on(websocket, :frame_received, &frame(:frame_received, url, &1))
    WebSocket.on(websocket, :close, fn _websocket -> websocket_closed(url) end)
  end

  defp websocket_closed(url) do
    :telemetry.execute([:live_load, :websocket, :closed], %{count: 1, monotonic_time: System.monotonic_time()}, %{
      url: url
    })
  end

  # Text frames carry a string payload (opcode 1), binary frames `{:binary, data}` (opcode 2).
  defp frame(event, url, %{payload: {:binary, data}}), do: emit_frame(event, url, data, 2)
  defp frame(event, url, %{payload: data}), do: emit_frame(event, url, data, 1)

  defp emit_frame(event, url, data, opcode) do
    :telemetry.execute(
      [:live_load, :websocket, event],
      %{payload_size: byte_size(data), monotonic_time: System.monotonic_time()},
      %{url: url, opcode: opcode}
    )
  end

  defp timing_to_native(timing) when timing < 0, do: -1
  defp timing_to_native(timing), do: System.convert_time_unit(round(timing * 1000), :microsecond, :native)
end
