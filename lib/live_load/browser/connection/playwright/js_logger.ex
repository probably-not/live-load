defmodule LiveLoad.Browser.Connection.Playwright.JsLogger do
  @moduledoc false
  @behaviour PlaywrightEx.JsLogger

  require Logger

  @impl true
  def log(_level, "__LIVELOAD||" <> encoded, msg) do
    case JSON.decode(encoded) do
      {:ok, telemetry} ->
        location = location(msg)
        Logger.info(if(location, do: "#{inspect(telemetry)} (#{location})", else: inspect(telemetry)))

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

  defp location(%{params: %{location: %{url: ""}}}), do: nil
  defp location(%{params: %{location: %{url: url, line_number: 0}}}), do: url
  defp location(%{params: %{location: %{url: url, line_number: line}}}), do: "#{url}:#{line}"
  defp location(%{params: %{location: %{url: url}}}), do: url
  defp location(_), do: nil
end
