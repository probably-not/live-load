defmodule LiveLoad.Browser.Connection.Playwright.Metrics.Debugger do
  @moduledoc false
  # `LiveLoad.Browser.Connection.Playwright.Metrics.Debugger` is a simple
  # Telemetry listener that subscribes to the unknown telemetry event
  # emitted by the `LiveLoad.Browser.Connection.Playwright.Metrics`
  # GenServer and writes these events to a file. This provides some
  # simple debugging capabilities to identify whether there are events
  # that are being missed that should be tracked.

  use GenServer

  def start_link(file_path) do
    case GenServer.start_link(__MODULE__, file_path, name: __MODULE__) do
      {:ok, pid} when is_pid(pid) -> {:ok, tap(pid, &install/1)}
      other -> other
    end
  end

  def stop(server \\ __MODULE__) do
    :ok = GenServer.stop(server)
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
      [:live_load, :unknown_playwright_message]
    ]
  end

  @impl true
  def init(file_path) do
    {:ok, File.open!(file_path, [:binary, :read, :write, :append])}
  end

  @impl true
  def handle_cast({:telemetry, event, measurements, metadata}, file) do
    IO.binwrite(file, [JSON.encode_to_iodata!(%{event: event, measurements: measurements, metadata: metadata}), "\n"])
    {:noreply, file}
  end
end
