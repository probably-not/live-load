defmodule LiveLoad.Scenario.Context do
  @moduledoc ~S"""
  A context struct that is given to every `c:LiveLoad.Scenario.run/3` callback while running a `LiveLoad.Scenario`.
  It wraps the `LiveLoad.Browser.Context` details for the runner and provides a simple API for interacting with the browser.

  This module's API is based on Plug.Conn, using the following patterns:
  - A scenario that is `:halted?` at any point in the scenario will short-circuit and not run any other functions.
  - A scenario that has an `:error` at any point in the scenario will short-circuit and not run any other functions.
  - Values can be extracted from the page through the available functions and `assign`ed onto the context for future use in the pipeline.

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
  """
  @spec halted?(context :: t()) :: boolean()
  def halted?(%Context{halted?: halted?}), do: halted?

  @doc """
  Checks to see if the `LiveLoad.Scenario.Context` failed to complete.

  Failure occurs when an error occurs while the `LiveLoad.Scenario` is running.
  """
  @spec failed?(context :: t()) :: boolean()
  def failed?(%Context{error: error}), do: not is_nil(error)

  @doc """
  Navigates to the given URL.
  """
  @spec navigate(context :: t(), url :: resolvable(String.t())) :: t()
  def navigate(%Context{} = ctx, url), do: run(ctx, :navigate, [url])

  @doc """
  Waits for an element that matches the given selector to appear on the current page.
  """
  @spec wait_for_selector(context :: t(), selector :: resolvable(String.t())) :: t()
  def wait_for_selector(%Context{} = ctx, selector), do: run(ctx, :wait_for_selector, [selector])

  defp run(%Context{halted?: true} = ctx, _op, _args) do
    ctx
  end

  defp run(%Context{error: %Error{}} = ctx, _op, _args) do
    ctx
  end

  defp run(%Context{error: nil, halted?: false} = ctx, op, args) do
    current_step = ctx.step + 1
    ctx = %{ctx | step: current_step}

    resolved_args = Enum.map(args, &resolve(ctx, &1))

    try do
      case apply(LiveLoad.Browser.Context, op, [ctx.browser_context | resolved_args]) do
        {:ok, new_browser_ctx} ->
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

  defp resolve(%Context{} = ctx, f) when is_function(f, 1), do: f.(ctx)
  defp resolve(_ctx, value), do: value
end
