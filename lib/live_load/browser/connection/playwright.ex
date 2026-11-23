defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc """
  An implementation of `LiveLoad.Browser.Connection` that uses the `Playwright` library (Hex package `playwright_ex`) to run and communicate with a Playwright instance.
  """

  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser
  alias LiveLoad.Browser.Connection.Playwright.JsLogger
  alias LiveLoad.Browser.Connection.Playwright.Metrics
  alias LiveLoad.Browser.Connection.Playwright.Supervisor
  alias LiveLoad.Browser.Context

  @typedoc """
  Options passed in to the connection for Playwright.

  ## Options
  - `:command_timeout` (`t:timeout/0`): A timeout for commands sent to the Playwright instance.
  """
  @type connection_option() :: {:command_timeout, timeout()}

  @impl true
  @doc false
  defdelegate child_spec(opts), to: Supervisor

  @impl true
  @doc false
  def browser_contexts_per_core, do: 2

  @impl true
  @doc false
  def browser_memory_usage_bytes, do: 250 * 1024 * 1024

  @impl true
  @doc false
  def context_memory_usage_bytes, do: 150 * 1024 * 1024

  @impl true
  @doc false
  def drain_metrics(%Browser{} = browser) do
    :ok =
      browser.supervisor_pid
      |> Browser.Supervisor.connection_pid!()
      |> Supervisor.metrics_pid!()
      |> Metrics.drain()

    :ok
  end

  @impl true
  @doc false
  def new_context(%Browser{} = browser) do
    playwright_browser = browser.private.playwright_connection_browser

    with {:ok, context} <- Playwright.Browser.new_context(playwright_browser),
         :ok <- Playwright.BrowserContext.set_default_timeout(context, command_timeout(browser)),
         :ok <- JsLogger.attach(context),
         {:ok, _} <- Playwright.BrowserContext.add_init_script(context, browser_telemetry_script!()) do
      browser
      |> Context.new()
      |> Context.put_private(:playwright_connection_context, context)
      |> then(&{:ok, &1})
    end
  end

  @impl true
  @doc false
  def context_storage_snapshot(%Context{} = context) do
    playwright_context = context.private.playwright_connection_context

    with {:ok, storage_state} <-
           Playwright.BrowserContext.storage_state(playwright_context, indexed_db: true) do
      {:ok, {context, storage_state}}
    end
  end

  @impl true
  @doc false
  def restore_context_storage(%Context{} = context, snapshot) when is_map(snapshot) do
    playwright_context = context.private.playwright_connection_context

    with :ok <-
           Playwright.BrowserContext.set_storage_state(playwright_context, %{
             cookies: snapshot[:cookies] || snapshot["cookies"] || [],
             origins: snapshot[:origins] || snapshot["origins"] || []
           }) do
      {:ok, context}
    end
  end

  @impl true
  @doc false
  def restore_context_storage(%Context{} = _context, snapshot) do
    {:error, {:invalid_snapshot, snapshot}}
  end

  @doc false
  @impl true
  def reset_context_storage(%Context{} = context) do
    playwright_context = context.private.playwright_connection_context

    with :ok <- Playwright.BrowserContext.set_storage_state(playwright_context, %{cookies: [], origins: []}) do
      {:ok, context}
    end
  end

  @config_key {__MODULE__, :browser_telemetry_script}
  defp browser_telemetry_script! do
    # This isn't *really* safe, but it's a good enough solution.
    # Worst case, someone starts two browsers at the exact same time
    # and the persistent term is reset. Probably won't though...
    case :persistent_term.get(@config_key, nil) do
      nil ->
        :live_load
        |> Application.get_env(
          :playwright_browser_telemetry_script_path,
          Path.join(Application.app_dir(:live_load, "priv/static"), "liveview_telemetry.js")
        )
        |> File.read!()
        |> tap(&:persistent_term.put(@config_key, &1))

      script when is_binary(script) ->
        script
    end
  end

  @impl true
  @doc false
  def stop_context(%Context{} = context) do
    if playwright_context = context.private[:playwright_connection_context] do
      Playwright.BrowserContext.close(playwright_context)
    else
      :ok
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
  def reload(%Context{} = context) do
    if page = context.private[:playwright_connection_page] do
      with {:ok, _} <- Playwright.Page.reload(page) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def wait_for_selector(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             Playwright.Frame.wait_for_selector(frame, selector) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def click(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.click(frame, selector) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def fill(%Context{} = context, selector, value) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.fill(frame, selector, value) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def press(%Context{} = context, selector, key) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.press(frame, selector, key) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def check(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.check(frame, selector) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def uncheck(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.uncheck(frame, selector) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def select_option(%Context{} = context, selector, value) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             Playwright.Frame.select_option(frame, selector, value) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def select_multiple_options(%Context{} = context, selector, values) do
    select_option(context, selector, values)
  end

  @impl true
  @doc false
  def focus(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.focus(frame, selector) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def blur(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             frame
             |> Playwright.Frame.locator(selector)
             |> Playwright.Locator.blur() do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def hover(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.hover(frame, selector) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def drag_and_drop(%Context{} = context, source, target) do
    if frame = context.private[:playwright_connection_frame] do
      with :ok <-
             Playwright.Frame.drag_and_drop(frame, source, target) do
        {:ok, context}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def page_content(%Context{} = context) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, content} <-
             Playwright.Frame.content(frame) do
        {:ok, {context, content}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def inner_html(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, inner_html} <-
             Playwright.Frame.inner_html(frame, selector) do
        {:ok, {context, inner_html}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def inner_text(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, inner_text} <-
             Playwright.Frame.inner_text(frame, selector) do
        {:ok, {context, inner_text}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def text_content(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, text_content} <-
             Playwright.Frame.text_content(frame, selector) do
        {:ok, {context, text_content}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def input_value(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, input_value} <-
             Playwright.Frame.input_value(frame, selector) do
        {:ok, {context, input_value}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def get_attribute(%Context{} = context, selector, name) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, attribute} <-
             Playwright.Frame.get_attribute(frame, selector, name) do
        {:ok, {context, attribute}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def visible?(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, attribute} <-
             Playwright.Frame.is_visible(frame, selector) do
        {:ok, {context, attribute}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  @impl true
  @doc false
  def checked?(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, attribute} <-
             Playwright.Frame.is_checked(frame, selector) do
        {:ok, {context, attribute}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  defp initialize_context_frame(%Context{} = context) do
    playwright_context = context.private.playwright_connection_context

    case Playwright.BrowserContext.new_page(playwright_context) do
      {:ok, page} ->
        metrics =
          context.browser.supervisor_pid
          |> Browser.Supervisor.connection_pid!()
          |> Supervisor.metrics_pid!()

        :ok = Metrics.watch_page(metrics, page)

        context =
          context
          |> Context.put_private(:playwright_connection_page, page)
          |> Context.put_private(:playwright_connection_frame, Playwright.Page.main_frame(page))

        {:ok, context}

      {:error, _reason} = error ->
        error
    end
  end

  defp do_navigate(frame, %URI{} = url) do
    do_navigate(frame, URI.to_string(url))
  end

  defp do_navigate(frame, url) when is_binary(url) do
    Playwright.Frame.goto(frame, url)
  end

  @impl true
  @doc false
  def after_start(%Browser{} = browser) do
    with {:ok, playwright_browser} <-
           Supervisor.playwright_instance()
           |> Playwright.chromium()
           |> Playwright.BrowserType.launch(
             headless: true,
             timeout: command_timeout(browser),
             args: [
               "--disable-dev-shm-usage",
               "--disable-gpu",
               "--no-zygote",
               "--js-flags=--max-old-space-size=256"
             ]
           ) do
      {:ok, Browser.put_private(browser, :playwright_connection_browser, playwright_browser)}
    end
  end

  defp command_timeout(%Browser{connection: {_mod, opts}}) do
    opts[:command_timeout] || to_timeout(minute: 1)
  end
end
