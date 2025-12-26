defmodule LiveLoad.Browser.Connection do
  @moduledoc """
  `LiveLoad.Browser.Connection` defines a behaviour for how to connect to browsers with LiveLoad.
  By default, an implementation for a Playwright instance (`LiveLoad.Browser.Connection.Playwright`)
  is included in LiveLoad and can be looked at as reference implementation for implementing other browsers.
  """

  alias LiveLoad.Browser
  alias LiveLoad.Browser.Context

  @type t() :: module()

  @type context() :: term()
  @type page() :: term()
  @type element() :: term()

  @type option() :: LiveLoad.Browser.Connection.Playwright.option() | {atom(), term()}
  @type opts() :: [option()]

  #############################
  ##### Process Callbacks #####
  #############################
  @callback start_link(opts :: opts()) :: GenServer.on_start() | Supervisor.on_start()

  #############################
  ##### Browser Callbacks #####
  #############################
  @callback new_context(browser :: Browser.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback navigate(context :: Context.t(), url :: String.t() | URI.t()) :: {:ok, Context.t()} | {:error, term()}

  ##############################
  ## Lifecycle Hook Callbacks ##
  ##############################
  @callback before_start(browser :: Browser.t()) :: Browser.t()
  @callback after_start(browser :: Browser.t()) :: Browser.t()
  @callback before_stop(browser :: Browser.t()) :: Browser.t()
  @callback after_stop(browser :: Browser.t()) :: :ok

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour LiveLoad.Browser.Connection
      def before_start(browser), do: browser
      defoverridable before_start: 1

      def after_start(browser), do: browser
      defoverridable after_start: 1

      def before_stop(browser), do: browser
      defoverridable before_stop: 1

      def after_stop(browser), do: :ok
      defoverridable after_stop: 1
    end
  end

  ##############################
  ####### Connection API #######
  ##############################

  @doc false
  def new_context(%Browser{connection: {mod, _opts}} = browser) do
    mod.new_context(browser)
  end
end
