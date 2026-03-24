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

  @impl true
  def init(connection) do
    {:ok, {connection, File.open!("./event_log.jsonl", [:read, :write, :binary])}}
  end

  @impl true
  def handle_call({:watch_page, guid, timeout}, _from, {connection, outfile}) do
    :ok = PlaywrightEx.subscribe(guid, connection: connection)

    Enum.each([:console, :request, :response, :requestFinished, :requestFailed], fn event ->
      {:ok, _} =
        PlaywrightEx.Page.update_subscription(guid, event: event, enabled: true, timeout: timeout, connection: connection)
    end)

    {:reply, :ok, {connection, outfile}}
  end

  @impl true
  def handle_info({:playwright_msg, %{params: %{type: "Request"} = params} = _message}, {connection, outfile}) do
    :ok = PlaywrightEx.subscribe(params.guid, connection: connection)
    {:noreply, {connection, outfile}}
  end

  @impl true
  def handle_info({:playwright_msg, %{params: %{type: "WebSocket"} = params} = _message}, {connection, outfile}) do
    :ok = PlaywrightEx.subscribe(params.guid, connection: connection)
    {:noreply, {connection, outfile}}
  end

  @impl true
  def handle_info({:playwright_msg, _message}, {connection, outfile}) do
    {:noreply, {connection, outfile}}
  end
end
