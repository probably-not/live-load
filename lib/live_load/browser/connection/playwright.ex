defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc false

  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser
  alias LiveLoad.Browser.Context

  @type option() ::
          {:playwright_cli_path, Path.t()}
          | {:name, GenServer.name()}
          | {:playwright_version, Version.version()}
          | {:startup_timeout, pos_integer()}

  @impl true
  defdelegate start_link(opts), to: LiveLoad.Browser.Connection.Playwright.Supervisor
  defdelegate child_spec(opts), to: LiveLoad.Browser.Connection.Playwright.Supervisor

  @impl true
  def new_context(%Browser{} = browser) do
    playwright_browser = browser.private.playwright_connection_browser

    case PlaywrightEx.Browser.new_context(playwright_browser.guid, timeout: 10_000) do
      {:ok, context} ->
        browser
        |> Context.new()
        |> Context.put_private(:playwright_connection_context, context)
        |> then(&{:ok, &1})

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def navigate(%Context{} = context, url) do
    if frame = context.private[:playwright_connection_frame] do
      do_navigate(frame, url)
      {:ok, context}
    else
      with {:ok, context} <- initialize_context_frame(context) do
        frame = context.private.playwright_connection_frame
        do_navigate(frame, url)
        {:ok, context}
      end
    end
  end

  defp initialize_context_frame(%Context{} = context) do
    playwright_context = context.private.playwright_connection_context

    case PlaywrightEx.BrowserContext.new_page(playwright_context.guid, timeout: 10_000) do
      {:ok, %{main_frame: frame}} -> {:ok, Context.put_private(context, :playwright_connection_frame, frame)}
      {:error, _reason} = error -> error
    end
  end

  defp do_navigate(frame, %URI{} = url) do
    do_navigate(frame, URI.to_string(url))
  end

  defp do_navigate(frame, url) when is_binary(url) do
    PlaywrightEx.Frame.goto(frame.guid, url: url, timeout: 10_000)
  end

  @impl true
  def after_start(%Browser{} = browser) do
    {:ok, playwright_browser} = PlaywrightEx.launch_browser(:chromium, timeout: 10_000)
    Browser.put_private(browser, :playwright_connection_browser, playwright_browser)
  end
end
