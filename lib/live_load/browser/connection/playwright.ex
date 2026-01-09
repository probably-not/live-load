defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc """
  An implementation of `LiveLoad.Browser.Connection` that uses the `PlaywrightEx` library to run and communicate with a Playwright instance.
  """

  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser
  alias LiveLoad.Browser.Context

  @typedoc """
  Options passed in to `PlaywrightEx` in order to start up the Playwright instance.
  """
  @type option() ::
          {:playwright_cli_path, Path.t()}
          | {:name, GenServer.name()}
          | {:playwright_version, Version.version()}
          | {:startup_timeout, pos_integer()}

  @impl true
  @doc false
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
  @doc false
  def navigate(%Context{} = context, url) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <- do_navigate(frame, url) do
        {:ok, context}
      end
    else
      with {:ok, context} <- initialize_context_frame(context),
           frame = context.private.playwright_connection_frame,
           {:ok, _} <- do_navigate(frame, url) do
        {:ok, context}
      end
    end
  end

  @impl true
  @doc false
  def wait_for_selector(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.wait_for_selector(frame.guid,
               selector: PlaywrightEx.Selector.build(selector),
               timeout: 10_000
             ) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
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
  @doc false
  def after_start(%Browser{} = browser) do
    {:ok, playwright_browser} = PlaywrightEx.launch_browser(:chromium, timeout: 10_000)
    Browser.put_private(browser, :playwright_connection_browser, playwright_browser)
  end
end
