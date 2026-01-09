defmodule LiveLoad.Scenario.Context do
  @moduledoc ~S"""
  A context struct that is given to every `c:LiveLoad.Scenario.run/3` callback while running a `LiveLoad.Scenario`.
  It wraps the `LiveLoad.Browser.Context` details for the runner and provides a simple API for interacting with the browser.

  This module's API is based on Plug.Conn, using the following patterns:
  - A scenario that is `:halted` at any point in the scenario will short-circuit and not run any other functions.
  - Values can be extracted from the page through the available functions and `assign`ed onto the context for future use in the pipeline.

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

  @type t() :: %__MODULE__{
          browser_context: LiveLoad.Browser.Context.t(),
          assigns: %{optional(atom()) => term()}
        }

  defstruct [:browser_context, assigns: %{}]

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
end
