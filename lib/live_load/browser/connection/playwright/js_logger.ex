defmodule LiveLoad.Browser.Connection.Playwright.JsLogger do
  @moduledoc false
  @behaviour PlaywrightEx.JsLogger

  require Logger

  @impl true
  def log(_level, "__LIVELOAD||" <> encoded, msg) do
    case LiveLoad.JSON.decode(encoded) do
      {:ok, %{"kind" => kind} = telemetry} ->
        emit_telemetry(kind, telemetry, msg.params.page.guid)

      {:error, reason} ->
        Logger.error([
          "[LiveLoad.Browser.Connection.Playwright.JsLogger] Unable to decode browser telemetry: ",
          inspect(encoded),
          "; ",
          Exception.format_exit(reason)
        ])
    end
  end

  @impl true
  def log(level, text, msg) do
    location = location(msg)
    Logger.log(level, if(location, do: "#{text} (#{location})", else: text))
  end

  defp emit_telemetry("phx_loading", %{"phase" => "start"} = data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :page_loading, :start],
      %{system_time: System.system_time(), monotonic_time: System.monotonic_time()},
      %{kind: data["info"], span_id: data["span_id"], page_guid: page_guid}
    )
  end

  defp emit_telemetry("phx_loading", %{"phase" => "stop"} = data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :page_loading, :stop],
      %{duration: browser_duration_to_native(data["duration_ms"]), monotonic_time: System.monotonic_time()},
      %{kind: data["info"], span_id: data["span_id"], page_guid: page_guid}
    )
  end

  defp emit_telemetry("phx_loading", %{"phase" => "canceled"} = data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :page_loading, :exception],
      %{duration: browser_duration_to_native(data["duration_ms"]), monotonic_time: System.monotonic_time()},
      %{kind: data["info"], span_id: data["span_id"], page_guid: page_guid}
    )
  end

  defp emit_telemetry("loading_class", %{"phase" => "start"} = data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :loading_class, :start],
      %{system_time: System.system_time(), monotonic_time: System.monotonic_time()},
      %{class: data["cls"], id: data["id"], span_id: data["span_id"], page_guid: page_guid}
    )
  end

  defp emit_telemetry("loading_class", %{"phase" => "stop"} = data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :loading_class, :stop],
      %{duration: browser_duration_to_native(data["duration_ms"]), monotonic_time: System.monotonic_time()},
      %{class: data["cls"], id: data["id"], span_id: data["span_id"], page_guid: page_guid}
    )
  end

  defp emit_telemetry("phx_navigate", data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :navigate],
      %{monotonic_time: System.monotonic_time()},
      %{href: data["href"], type: data["type"], page_guid: page_guid}
    )
  end

  defp emit_telemetry("lv_connected", data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :connected],
      %{duration: browser_duration_to_native(data["duration_ms"]), monotonic_time: System.monotonic_time()},
      %{span_id: data["span_id"], page_guid: page_guid}
    )
  end

  defp emit_telemetry("lv_disconnected", _data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :disconnected],
      %{monotonic_time: System.monotonic_time()},
      %{page_guid: page_guid}
    )
  end

  defp emit_telemetry("lv_reconnected", data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :reconnected],
      %{duration: browser_duration_to_native(data["duration_ms"]), monotonic_time: System.monotonic_time()},
      %{page_guid: page_guid}
    )
  end

  defp emit_telemetry("browser_telemetry_init", data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :browser_telemetry, :init],
      %{monotonic_time: System.monotonic_time()},
      %{href: data["href"], page_guid: page_guid}
    )
  end

  defp emit_telemetry(unknown_kind, data, page_guid) do
    :telemetry.execute(
      [:live_load, :liveview, :browser_telemetry, :unknown],
      %{monotonic_time: System.monotonic_time()},
      %{kind: unknown_kind, data: data, page_guid: page_guid}
    )
  end

  defp browser_duration_to_native(duration), do: System.convert_time_unit(round(duration * 1000), :microsecond, :native)

  defp location(%{params: %{location: %{url: ""}}}), do: nil
  defp location(%{params: %{location: %{url: url, line_number: 0}}}), do: url
  defp location(%{params: %{location: %{url: url, line_number: line}}}), do: "#{url}:#{line}"
  defp location(%{params: %{location: %{url: url}}}), do: url
  defp location(_), do: nil
end
