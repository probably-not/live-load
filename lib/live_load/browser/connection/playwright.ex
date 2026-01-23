defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc """
  An implementation of `LiveLoad.Browser.Connection` that uses the `PlaywrightEx` library to run and communicate with a Playwright instance.
  """

  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser
  alias LiveLoad.Browser.Context

  @typedoc """
  Options passed in to the connection for Playwright.

  ## Options
  - `:command_timeout` (`t:timeout/0`): A timeout for commands sent to the Playwright instance.
  """
  @type connection_option() :: {:command_timeout, timeout()}

  @impl true
  @doc false
  def new_context(%Browser{} = browser) do
    playwright_browser = browser.private.playwright_connection_browser

    case PlaywrightEx.Browser.new_context(playwright_browser.guid, timeout: command_timeout(browser)) do
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
  def stop_context(%Context{} = context) do
    if playwright_context = context.private[:playwright_connection_context] do
      PlaywrightEx.BrowserContext.close(playwright_context.guid, timeout: command_timeout(context.browser))
    else
      :ok
    end
  end

  @impl true
  @doc false
  def navigate(%Context{} = context, url) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <- do_navigate(frame, url, command_timeout(context.browser)) do
        {:ok, context}
      end
    else
      with {:ok, context} <- initialize_context_frame(context),
           frame = context.private.playwright_connection_frame,
           {:ok, _} <- do_navigate(frame, url, command_timeout(context.browser)) do
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
               timeout: command_timeout(context.browser)
             ) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  def page_content(%Context{} = context) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, content} <- PlaywrightEx.Frame.content(frame.guid, timeout: command_timeout(context.browser)) do
        {:ok, {context, content}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  def inner_html(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, inner_html} <-
             PlaywrightEx.Frame.inner_html(frame.guid,
               selector: PlaywrightEx.Selector.build(selector),
               timeout: command_timeout(context.browser)
             ) do
        {:ok, {context, inner_html}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  defp initialize_context_frame(%Context{} = context) do
    playwright_context = context.private.playwright_connection_context

    case PlaywrightEx.BrowserContext.new_page(playwright_context.guid, timeout: command_timeout(context.browser)) do
      {:ok, %{main_frame: frame}} -> {:ok, Context.put_private(context, :playwright_connection_frame, frame)}
      {:error, _reason} = error -> error
    end
  end

  defp do_navigate(frame, %URI{} = url, timeout) do
    do_navigate(frame, URI.to_string(url), timeout)
  end

  defp do_navigate(frame, url, timeout) when is_binary(url) do
    PlaywrightEx.Frame.goto(frame.guid, url: url, timeout: timeout)
  end

  @impl true
  @doc false
  def after_start(%Browser{} = browser) do
    {:ok, playwright_browser} = PlaywrightEx.launch_browser(:chromium, timeout: command_timeout(browser))
    Browser.put_private(browser, :playwright_connection_browser, playwright_browser)
  end

  defp command_timeout(%Browser{connection: {_mod, opts}}) do
    opts[:command_timeout] || to_timeout(second: 10)
  end
end
