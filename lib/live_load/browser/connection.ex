defmodule LiveLoad.Browser.Connection do
  @moduledoc """
  `LiveLoad.Browser.Connection` defines a behaviour for how to connect to browsers with LiveLoad.
  By default, an implementation for a Playwright instance (`LiveLoad.Browser.Connection.Playwright`)
  is included in LiveLoad and can be looked at as reference implementation for implementing other browsers.
  """

  @type t() :: module()

  @type context() :: term()
  @type page() :: term()
  @type element() :: term()

  @type option() :: LiveLoad.Browser.Connection.Playwright.option() | {atom(), term()}
  @type opts() :: [option()]

  @callback start_link(opts :: opts()) :: GenServer.on_start() | Supervisor.on_start()
end
