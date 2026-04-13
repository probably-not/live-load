defmodule LiveLoad.Browser.Connection.Playwright do
  @moduledoc """
  An implementation of `LiveLoad.Browser.Connection` that uses the `PlaywrightEx` library to run and communicate with a Playwright instance.
  """

  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser
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
  def browser_memory_usage_bytes, do: 250 * 1024 * 1024

  @impl true
  @doc false
  def context_memory_usage_bytes, do: 150 * 1024 * 1024

  @impl true
  @doc false
  def drain_metrics(%Browser{} = browser) do
    playwright_browser = browser.private.playwright_connection_browser
    _ = PlaywrightEx.Connection.initializer!(Supervisor.playwright_connection_name(), playwright_browser.guid)

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

    with {:ok, context} <-
           PlaywrightEx.Browser.new_context(playwright_browser.guid,
             connection: Supervisor.playwright_connection_name(),
             timeout: command_timeout(browser)
           ),
         {:ok, _} <-
           PlaywrightEx.BrowserContext.add_init_script(context.guid,
             source: browser_telemetry_script!(),
             connection: Supervisor.playwright_connection_name(),
             timeout: command_timeout(browser)
           ) do
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
           PlaywrightEx.BrowserContext.storage_state(playwright_context.guid,
             indexedDB: true,
             connection: Supervisor.playwright_connection_name(),
             timeout: command_timeout(context.browser)
           ) do
      {:ok, {context, storage_state}}
    end
  end

  @impl true
  @doc false
  def restore_context_storage(%Context{} = context, snapshot) when is_map(snapshot) do
    playwright_context = context.private.playwright_connection_context

    with {:ok, _} <-
           PlaywrightEx.BrowserContext.set_storage_state(playwright_context.guid,
             cookies: snapshot[:cookies] || snapshot["cookies"] || [],
             origins: snapshot[:origins] || snapshot["origins"] || [],
             connection: Supervisor.playwright_connection_name(),
             timeout: command_timeout(context.browser)
           ) do
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

    with {:ok, _} <-
           PlaywrightEx.BrowserContext.set_storage_state(playwright_context.guid,
             cookies: [],
             origins: [],
             connection: Supervisor.playwright_connection_name(),
             timeout: command_timeout(context.browser)
           ) do
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
      with {:ok, _} <-
             PlaywrightEx.BrowserContext.close(playwright_context.guid,
               connection: Supervisor.playwright_connection_name(),
               timeout: command_timeout(context.browser)
             ) do
        :ok
      end
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
  def reload(%Context{} = context) do
    if page_id = context.private[:playwright_connection_page_id] do
      with {:ok, _} <-
             PlaywrightEx.Page.reload(page_id,
               connection: Supervisor.playwright_connection_name(),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.wait_for_selector(frame.guid,
               connection: Supervisor.playwright_connection_name(),
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
  @doc false
  def click(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.click(frame.guid,
               connection: Supervisor.playwright_connection_name(),
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
  @doc false
  def fill(%Context{} = context, selector, value) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.fill(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               value: value,
               timeout: command_timeout(context.browser)
             ) do
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
      with {:ok, _} <-
             PlaywrightEx.Frame.press(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               key: key,
               timeout: command_timeout(context.browser)
             ) do
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
      with {:ok, _} <-
             PlaywrightEx.Frame.check(frame.guid,
               connection: Supervisor.playwright_connection_name(),
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
  @doc false
  def uncheck(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.uncheck(frame.guid,
               connection: Supervisor.playwright_connection_name(),
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
  @doc false
  def select_option(%Context{} = context, selector, value) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.select_option(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               options: value,
               timeout: command_timeout(context.browser)
             ) do
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
      with {:ok, _} <-
             PlaywrightEx.Frame.focus(frame.guid,
               connection: Supervisor.playwright_connection_name(),
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
  @doc false
  def blur(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.blur(frame.guid,
               connection: Supervisor.playwright_connection_name(),
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
  @doc false
  def hover(%Context{} = context, selector) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.hover(frame.guid,
               connection: Supervisor.playwright_connection_name(),
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
  @doc false
  def drag_and_drop(%Context{} = context, source, target) do
    if frame = context.private[:playwright_connection_frame] do
      with {:ok, _} <-
             PlaywrightEx.Frame.drag_and_drop(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               source: PlaywrightEx.Selector.build(source),
               target: PlaywrightEx.Selector.build(target),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.content(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.inner_html(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.inner_text(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.text_content(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.input_value(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.get_attribute(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               name: name,
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.is_visible(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               timeout: command_timeout(context.browser)
             ) do
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
             PlaywrightEx.Frame.is_checked(frame.guid,
               connection: Supervisor.playwright_connection_name(),
               selector: PlaywrightEx.Selector.build(selector),
               timeout: command_timeout(context.browser)
             ) do
        {:ok, {context, attribute}}
      end
    else
      {:error, :no_navigation_occurred}
    end
  end

  defp initialize_context_frame(%Context{} = context) do
    playwright_context = context.private.playwright_connection_context

    case PlaywrightEx.BrowserContext.new_page(playwright_context.guid,
           connection: Supervisor.playwright_connection_name(),
           timeout: command_timeout(context.browser)
         ) do
      {:ok, %{guid: page_id, main_frame: frame}} ->
        metrics =
          context.browser.supervisor_pid
          |> Browser.Supervisor.connection_pid!()
          |> Supervisor.metrics_pid!()

        :ok = Metrics.watch_page(metrics, page_id)

        context =
          context
          |> Context.put_private(:playwright_connection_page_id, page_id)
          |> Context.put_private(:playwright_connection_frame, frame)

        {:ok, context}

      {:error, _reason} = error ->
        error
    end
  end

  defp do_navigate(frame, %URI{} = url, timeout) do
    do_navigate(frame, URI.to_string(url), timeout)
  end

  defp do_navigate(frame, url, timeout) when is_binary(url) do
    PlaywrightEx.Frame.goto(frame.guid, connection: Supervisor.playwright_connection_name(), url: url, timeout: timeout)
  end

  @impl true
  @doc false
  def after_start(%Browser{} = browser) do
    with {:ok, playwright_browser} <-
           PlaywrightEx.launch_browser(:chromium,
             headless: true,
             connection: Supervisor.playwright_connection_name(),
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
