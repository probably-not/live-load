defmodule LiveLoad.Browser.Connection do
  @moduledoc """
  `LiveLoad.Browser.Connection` defines a behaviour for how to connect to browsers with LiveLoad.

  By default, an implementation for a Playwright instance (`LiveLoad.Browser.Connection.Playwright`)
  is included in LiveLoad and can be looked at as reference implementation for implementing other browsers.
  """

  alias LiveLoad.Browser
  alias LiveLoad.Browser.Context

  @typedoc "Any module implementing the `LiveLoad.Browser.Connection` behaviour."
  @type t() :: module()

  @type option() :: LiveLoad.Browser.Connection.Playwright.connection_option() | {atom(), term()}
  @type opts() :: [option()]

  #############################
  ##### Process Callbacks #####
  #############################
  @callback child_spec(opts :: opts()) :: Supervisor.child_spec()

  #############################
  ##### Browser Callbacks #####
  #############################
  @callback new_context(browser :: Browser.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback stop_context(context :: Context.t()) :: :ok | {:error, term()}
  @callback navigate(context :: Context.t(), url :: String.t() | URI.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback wait_for_selector(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}

  ##############################
  ## Lifecycle Hook Callbacks ##
  ##############################

  @doc "A hook called before the supervision tree for the browser is initialized in `LiveLoad.Browser.start_link/2`"
  @callback before_start(browser :: Browser.t()) :: Browser.t()

  @doc "A hook called after the supervision tree for the browser is initialized in `LiveLoad.Browser.start_link/2`."
  @callback after_start(browser :: Browser.t()) :: Browser.t()

  @doc "A hook called before the supervision tree for the browser is stopped in `LiveLoad.Browser.stop/3`"
  @callback before_stop(browser :: Browser.t()) :: Browser.t()

  @doc "A hook called after the supervision tree for the browser is stopped in `LiveLoad.Browser.stop/3`"
  @callback after_stop(browser :: Browser.t()) :: :ok

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour LiveLoad.Browser.Connection

      @doc false
      def child_spec(_opts), do: %{id: __MODULE__, start: {Function, :identity, [:ignore]}, restart: :temporary}
      defoverridable child_spec: 1

      @doc false
      def before_start(browser), do: browser
      defoverridable before_start: 1

      @doc false
      def after_start(browser), do: browser
      defoverridable after_start: 1

      @doc false
      def before_stop(browser), do: browser
      defoverridable before_stop: 1

      @doc false
      def after_stop(browser), do: :ok
      defoverridable after_stop: 1
    end
  end
end
