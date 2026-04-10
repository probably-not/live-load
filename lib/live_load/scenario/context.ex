defmodule LiveLoad.Scenario.Context do
  @moduledoc ~S"""
  A context struct that is given to every `c:LiveLoad.Scenario.run/3` callback while running a `LiveLoad.Scenario`.
  It wraps the `LiveLoad.Browser.Context` details for the runner and provides a simple API for interacting with the browser.

  This module's API is based on Plug.Conn, using the following patterns:
  - A scenario that is `:halted?` at any point in the scenario will short-circuit and not run any other functions.
  - A scenario that has an `:error` at any point in the scenario will short-circuit and not run any other functions.
  - Values can be extracted from the page through the available functions and `assign`ed onto the context for future use in the pipeline.

  ## Scenario Context Lifecycle

  A `LiveLoad.Scenario.Context` is created once per user process at the start of the load test, before
  the scenario's `c:LiveLoad.Scenario.run/3` callback is called for the first time. It wraps the
  `LiveLoad.Browser.Context` that was created for that user, and is then passed into `c:LiveLoad.Scenario.run/3`
  as the first argument on every iteration of the scenario.

  The same context is reused across all iterations of a scenario for a given user. This means that
  any `assigns` set during one iteration will still be present on the context at the start of the next
  iteration. If you want to start each iteration with a clean set of assigns, you can call `reset_assigns/1`
  at the start of your `c:LiveLoad.Scenario.run/3` callback.

  ## Halting and Errors

  Halting and errors are mutually exclusive:
  - A scenario can be halted by calling the `halt/1` function in order to mark the scenario as halted.
  - A scenario will be marked with an error whenever any error, exception, or exit occurs while an operation is running.

  The reason for this mutual exclusivity is to preserve the reason for a scenario not completing. Errors are unexpected
  occurences that may happen for any number of reasons and are marked as such to ensure that any consumers of LiveLoad
  are able to understand what errors are happening in their application while load testing their sites. However, halting
  is manually marked and is a decision by the writer of the scenario. Halting can be used to simply short-circuit a scenario
  should the writer decide that it can be short-circuited at any point during the scenario's run.

  As such, when calling `halt/1`, a scenario will only be marked has halted if no error has occured in the pipeline in order
  to preserve the reason for the scenario not completing.

  Two helper functions, `halted?/1` and `failed?/1` are provided in order to determine if a scenario failed or was halted manually.

  A `LiveLoad.Scenario.Context` which is `halted?` or `failed?` will stop the `LiveLoad.Scenario` from iterating any further, and no more
  iterations will occur for this user's process.

  ## Assigns

  All functions exposed on the API accept both a raw value and a 1-arity function so that you can get values from the context and its assigns.

  For example, if you simple need to click on a button with a specific hard-coded ID, you might write something like this:

  ```
  click(context, "#submit")
  ```

  However, if the button may have a dynamic ID, you can pass in a 1-arity function and build the ID based on the assigns:

  ```
  click(context, &"##{&1.assigns.button_id}")
  ```
  """

  alias __MODULE__
  alias LiveLoad.Scenario.Error

  @type t() :: %__MODULE__{
          browser_context: LiveLoad.Browser.Context.t(),
          assigns: %{optional(atom()) => term()},
          halted?: boolean(),
          step: non_neg_integer(),
          error: Error.t() | nil
        }

  @typedoc """
  A resolvable variable given to operations on the `LiveLoad.Scenario.Context`.

  Can either be a value, or a 1-arity function that receives a `LiveLoad.Scenario.Context`
  and returns a value.
  """
  @type resolvable(value) :: value | (t() -> value)

  @typedoc """
  A key passed in to the `:as` option when using functions that extract values from the context.

  Values that are extracted can be specified to be assigned to the context's assigns via the `:as`
  option, which can receive an `t:atom/0`, or a 1-arity function which may return either an `t:atom/0`
  or a `t:map/0` of `t:atom/0` keys to values which will be merged onto the context's assigns.
  """
  @type assigned_as() :: atom() | (term() -> atom()) | (term() -> %{atom() => term()})

  defstruct [:browser_context, :error, halted?: false, assigns: %{}, step: 0]

  @doc false
  def new(%LiveLoad.Browser.Context{} = browser_context) do
    %Context{browser_context: browser_context}
  end

  @doc """
  Assigns a value to a key in the context.

  The `assigns` storage is meant to be used to store values in the connection
  so that other operations in your scenario's pipeline can access them.
  The `assigns` storage is a map.
  """
  @spec assign(context :: t(), key :: atom(), value :: term()) :: t
  def assign(%Context{assigns: assigns} = context, key, value) when is_atom(key) do
    %{context | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Resets all of the assigns on the context.

  During a `LiveLoad.Scenario`, the scenario will loop and run many iterations per user process.
  The `LiveLoad.Scenario.Context` is maintained across the loops, so that you can use assigns
  from a previous loop in order to take new actions on the previous data.

  See `assign/3` for information about the `assigns` storage.
  """
  @spec reset_assigns(context :: t()) :: t
  def reset_assigns(%Context{} = context) do
    %{context | assigns: %{}}
  end

  @doc """
  Clears a specific assign on the context.

  After clearing this key will no longer be available and assertive access will cause an exception.

  See `assign/3` for information about the `assigns` storage.
  """
  @spec clear_assign(context :: t(), key :: atom()) :: t
  def clear_assign(%Context{assigns: assigns} = context, key) when is_atom(key) do
    %{context | assigns: Map.delete(assigns, key)}
  end

  @doc """
  Updates a value under a specified key in the context.

  Raises a `KeyError` exception if the specified key does not exist on the assigns.

  See `assign/3` for information about the `assigns` storage.
  """
  @spec update_assign!(context :: t(), key :: atom(), (term() -> term())) :: t
  def update_assign!(%Context{assigns: assigns} = context, key, update_fn) when is_atom(key) do
    %{context | assigns: Map.update!(assigns, key, update_fn)}
  end

  @doc """
  Halts a `LiveLoad.Scenario` by preventing any further operations to take place on the context.

  If the scenario has already had an error, this results in a No-Op and the context will not be marked
  as halted in order to preserve the error.
  """
  @spec halt(context :: t()) :: t()
  def halt(%Context{error: nil} = ctx), do: %{ctx | halted?: true}
  def halt(%Context{error: %Error{}} = ctx), do: ctx

  @doc """
  Checks to see if the `LiveLoad.Scenario.Context` was halted.

  Halting occurs when the `halt/1` function is called on the context directly.

  Allowed in guard tests.
  """
  defguard halted?(context) when context.halted?

  @doc """
  Checks to see if the `LiveLoad.Scenario.Context` failed to complete.

  Failure occurs when an error occurs while the `LiveLoad.Scenario` is running.

  Allowed in guard tests.
  """
  defguard failed?(context) when not is_nil(context.error)

  @doc """
  Gets a snapshot of the current storage state of the browser context.

  This is a serializable storage snapshot that contains the current browser context's cookies, local storage, and session storage.

  This type is intentionally left as an ambiguous term, as it is meant to be usable as a storage and restoration mechanism,
  however it is not guaranteed to be uniform across different browser connections.

  ## Options

  * `:as` - an atom key to place the storage snapshot under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec context_storage_snapshot(context :: t(), opts :: [{:as, assigned_as()}]) :: t()
  def context_storage_snapshot(%Context{} = ctx, opts \\ []), do: run(ctx, :context_storage_snapshot, [], opts)

  @doc """
  Restores the storage state of the browser context from a previously stored snapshot.
  """
  @spec restore_context_storage(context :: t(), snapshot :: resolvable(term())) :: t()
  def restore_context_storage(%Context{} = ctx, snapshot), do: run(ctx, :restore_context_storage, [snapshot])

  @doc """
  Resets the storage state of the current browser context to an empty state.

  This will clear all cookies, local storage and session storage of the browser context.
  """
  @spec reset_context_storage(context :: t()) :: t()
  def reset_context_storage(%Context{} = ctx), do: run(ctx, :reset_context_storage, [])

  @doc """
  Navigates to the given URL.
  """
  @spec navigate(context :: t(), url :: resolvable(String.t())) :: t()
  def navigate(%Context{} = ctx, url), do: run(ctx, :navigate, [url])

  @doc """
  Reloads the current page.
  """
  @spec reload(context :: t()) :: t()
  def reload(%Context{} = ctx), do: run(ctx, :reload, [])

  @doc """
  Waits for an element that matches the given selector to appear on the current page.
  """
  @spec wait_for_selector(context :: t(), selector :: resolvable(String.t())) :: t()
  def wait_for_selector(%Context{} = ctx, selector), do: run(ctx, :wait_for_selector, [selector])

  @doc """
  Clicks an element that matches the given selector on the current page.
  """
  @spec click(context :: t(), selector :: resolvable(String.t())) :: t()
  def click(%Context{} = ctx, selector), do: run(ctx, :click, [selector])

  @doc """
  Fills an input element that matches the given selector on the current page with the given value.

  Passing an empty string as the value will clear the input's value.
  """
  @spec fill(context :: t(), selector :: resolvable(String.t()), value :: resolvable(String.t())) :: t()
  def fill(%Context{} = ctx, selector, value), do: run(ctx, :fill, [selector, value])

  @doc """
  Focuses an element that matches the given selector on the current page and activates the given key.
  """
  @spec press(context :: t(), selector :: resolvable(String.t()), key :: resolvable(String.t())) :: t()
  def press(%Context{} = ctx, selector, key), do: run(ctx, :press, [selector, key])

  @doc """
  Clears an input element that matches the given selector on the current page.
  """
  @spec clear(context :: t(), selector :: resolvable(String.t())) :: t()
  def clear(%Context{} = ctx, selector), do: fill(ctx, selector, "")

  @doc """
  Checks a checkbox or radio button element that matches the given selector on the current page.
  """
  @spec check(context :: t(), selector :: resolvable(String.t())) :: t()
  def check(%Context{} = ctx, selector), do: run(ctx, :check, [selector])

  @doc """
  Unchecks a checkbox or radio button element that matches the given selector on the current page.
  """
  @spec uncheck(context :: t(), selector :: resolvable(String.t())) :: t()
  def uncheck(%Context{} = ctx, selector), do: run(ctx, :uncheck, [selector])

  @doc """
  Selects an option on a select element that matches the given selector on the current page.
  """
  @spec select_option(context :: t(), selector :: resolvable(String.t()), value :: resolvable(String.t())) :: t()
  def select_option(%Context{} = ctx, selector, value), do: run(ctx, :select_option, [selector, value])

  @doc """
  Selects multiple options on a select element that matches the given selector on the current page.
  """
  @spec select_multiple_options(context :: t(), selector :: resolvable(String.t()), values :: resolvable([String.t()])) ::
          t()
  def select_multiple_options(%Context{} = ctx, selector, values),
    do: run(ctx, :select_multiple_options, [selector, values])

  @doc """
  Focuses an element that matches the given selector on the current page.
  """
  @spec focus(context :: t(), selector :: resolvable(String.t())) :: t()
  def focus(%Context{} = ctx, selector), do: run(ctx, :focus, [selector])

  @doc """
  Blurs an element that matches the given selector on the current page.
  """
  @spec blur(context :: t(), selector :: resolvable(String.t())) :: t()
  def blur(%Context{} = ctx, selector), do: run(ctx, :blur, [selector])

  @doc """
  Hovers over an element that matches the given selector on the current page.
  """
  @spec hover(context :: t(), selector :: resolvable(String.t())) :: t()
  def hover(%Context{} = ctx, selector), do: run(ctx, :hover, [selector])

  @doc """
  Drags from the source element matching the given selector to the target element matching the given selector.
  """
  @spec drag_and_drop(context :: t(), source :: resolvable(String.t()), target :: resolvable(String.t())) :: t()
  def drag_and_drop(%Context{} = ctx, source, target), do: run(ctx, :drag_and_drop, [source, target])

  @doc """
  Detects whether or not the current page is a LiveView.
  """
  @spec ensure_liveview(context :: t()) :: t()
  def ensure_liveview(%Context{} = ctx), do: wait_for_selector(ctx, "[data-phx-session]")

  @doc """
  Waits for a LiveView to be fully connected.
  """
  @spec wait_for_liveview(context :: t()) :: t()
  def wait_for_liveview(%Context{} = ctx), do: wait_for_selector(ctx, ".phx-connected")

  @typedoc """
  One of the loading class types that Phoenix adds to elements when events are in-flight on the `Phoenix.LiveView.Socket`.
  """
  @type phoenix_loading_type() :: :click | :submit | :change | :focus | :blur | :keydown | :keyup

  @doc """
  Waits for a phx-*-loading attribute to be removed from an element.
  Useful for waiting for LiveView event handling to complete.
  """
  @spec wait_for_phx_loading_completion(
          context :: t(),
          type :: phoenix_loading_type(),
          selector :: resolvable(String.t())
        ) ::
          t()
  def wait_for_phx_loading_completion(%Context{} = ctx, type, selector)
      when type in [:click, :submit, :change, :focus, :blur, :keydown, :keyup] do
    selector = resolve(ctx, selector)
    wait_for_selector(ctx, "#{selector}:not(.phx-#{type}-loading)")
  end

  @doc """
  Submits a LiveView form by clicking its submit button.
  Waits for the form to no longer have the `phx-submit-loading` class applied.
  """
  @spec submit_form(context :: t(), form_selector :: resolvable(String.t())) :: t()
  def submit_form(%Context{} = ctx, form_selector) do
    ctx
    |> click("#{form_selector} [type=submit]")
    |> wait_for_phx_loading_completion(:submit, form_selector)
  end

  @doc """
  Extracts the current page's content and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec page_content(context :: t(), opts :: [{:as, assigned_as()}]) :: t()
  def page_content(%Context{} = ctx, opts \\ []), do: run(ctx, :page_content, [], opts)

  @doc """
  Extracts the innerHTML value of an element matching the given selector and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec inner_html(context :: t(), selector :: String.t(), opts :: [{:as, assigned_as()}]) :: t()
  def inner_html(%Context{} = ctx, selector, opts \\ []), do: run(ctx, :inner_html, [selector], opts)

  @doc """
  Extracts the innerText value of an element matching the given selector and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec inner_text(context :: t(), selector :: String.t(), opts :: [{:as, assigned_as()}]) :: t()
  def inner_text(%Context{} = ctx, selector, opts \\ []), do: run(ctx, :inner_text, [selector], opts)

  @doc """
  Extracts the textContent value of an element matching the given selector and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec text_content(context :: t(), selector :: String.t(), opts :: [{:as, assigned_as()}]) :: t()
  def text_content(%Context{} = ctx, selector, opts \\ []), do: run(ctx, :text_content, [selector], opts)

  @doc """
  Extracts the value of an input, textarea, or select element matching the given selector and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec input_value(context :: t(), selector :: String.t(), opts :: [{:as, assigned_as()}]) :: t()
  def input_value(%Context{} = ctx, selector, opts \\ []), do: run(ctx, :input_value, [selector], opts)

  @doc """
  Extracts the element attribute value for an element matching the given selector and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec get_attribute(context :: t(), selector :: String.t(), name :: String.t(), opts :: [{:as, assigned_as()}]) :: t()
  def get_attribute(%Context{} = ctx, selector, name, opts \\ []), do: run(ctx, :get_attribute, [selector, name], opts)

  @doc """
  Extracts whether or not an element matching the given selector is visible and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec visible?(context :: t(), selector :: String.t(), opts :: [{:as, assigned_as()}]) :: t()
  def visible?(%Context{} = ctx, selector, opts \\ []), do: run(ctx, :visible?, [selector], opts)

  @doc """
  Extracts whether or not a checkbox or radio button element matching the given selector is checked and assigns it to the `:as` option on the context's assigns.

  ## Options

  * `:as` - an atom key to place the page content under on the context's assigns.
  Alternatively, you can pass a 1-arity function which will be run with the returned value.
  The function must return either an atom, which will be used as the key, or a map of new assigns
  values that will be merged into the current assigns on the context.
  """
  @spec checked?(context :: t(), selector :: String.t(), opts :: [{:as, assigned_as()}]) :: t()
  def checked?(%Context{} = ctx, selector, opts \\ []), do: run(ctx, :checked?, [selector], opts)

  defp run(ctx, op, args, opts \\ [])

  defp run(%Context{halted?: true} = ctx, _op, _args, _opts) do
    ctx
  end

  defp run(%Context{error: %Error{}} = ctx, _op, _args, _opts) do
    ctx
  end

  defp run(%Context{error: nil, halted?: false} = ctx, op, args, opts) do
    current_step = ctx.step + 1
    ctx = %{ctx | step: current_step}

    resolved_args = Enum.map(args, &resolve(ctx, &1))

    try do
      case apply(LiveLoad.Browser.Context, op, [ctx.browser_context | resolved_args]) do
        {:ok, {%LiveLoad.Browser.Context{} = new_browser_ctx, value}} ->
          ctx = assign_as(ctx, value, opts[:as])
          %{ctx | browser_context: new_browser_ctx}

        {:ok, %LiveLoad.Browser.Context{} = new_browser_ctx} ->
          %{ctx | browser_context: new_browser_ctx}

        {:error, reason} ->
          %{ctx | error: %Error{step: current_step, op: op, args: resolved_args, reason: reason}}
      end
    rescue
      exception ->
        %{ctx | error: %Error{step: current_step, op: op, args: resolved_args, reason: exception}}
    catch
      :exit, reason ->
        %{ctx | error: %Error{step: current_step, op: op, args: resolved_args, reason: reason}}
    end
  end

  defp assign_as(ctx, value, as)

  defp assign_as(%Context{} = ctx, _value, nil) do
    ctx
  end

  defp assign_as(%Context{} = ctx, value, as) when is_function(as, 1) do
    case as.(value) do
      assigns when is_map(assigns) ->
        Enum.reduce(assigns, ctx, fn {key, value}, ctx -> assign(ctx, key, value) end)

      key when is_atom(key) ->
        assign(ctx, key, value)

      other ->
        raise RuntimeError, """
        When using the `:as` option and passing in a 1-arity function,
        the return value of the function must be either a map of new assigns
        or an atom to place the value under within the assigns.

        Expected:

        map of new assigns or atom.

        Got:

        #{inspect(other)}
        """
    end
  end

  defp assign_as(%Context{} = ctx, value, as) when is_atom(as) do
    assign(ctx, as, value)
  end

  defp resolve(%Context{} = ctx, f) when is_function(f, 1), do: f.(ctx)
  defp resolve(_ctx, value), do: value
end
