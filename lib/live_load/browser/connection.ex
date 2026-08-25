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

  @typedoc """
  Level of the support status that a feature has in specific connection implementations.

  These are used by the `c:LiveLoad.Browser.Connection.metadata/0` callback in order to
  allow different browser implementations to define which features they may not fully support.

  The different status levels represent different workarounds:
  - `:estimated`: Useful for when certain telemetry may not be fully supported as emitted by a browser,
    but can be estimated by different means.
  - `:instrumented`: Useful for when an implementation does not support the native telemetry of specific metrics,
    but the telemetry support can be instrumented manually via JavaScript injections into the browser.
  - `:unsupported`: Used when a feature or metrics is completely unsupported and cannot be estimated or instrumented manually.
  """
  @type support_status() :: :estimated | :instrumented | :unsupported

  @typedoc "Metadata returned by the `c:LiveLoad.Browser.Connection.metadata/0` callback to signal the support levels of various features and metrics."
  @type metadata() :: %{
          adapter: String.t(),
          unsupported_metrics: %{optional(String.t()) => support_status()},
          unsupported_features: %{optional(String.t()) => support_status()}
        }

  @doc """
  Different browser implementations may have different levels of implementation for certain features in the browser,
  such as storage implementations, or telemetry signals availability. In order to surface this information to the result and
  whoever is viewing the result, this callback can be implemented by a connection implementation in order to return information
  about different support statuses for various features.
  """
  @callback metadata() :: metadata()

  ####################################
  ##### Resource Usage Callbacks #####
  ####################################

  @doc """
  Different browser implementations may have different CPU requirements, depending on how they are implemented.
  The `LiveLoad.Cluster` initialization procedure uses this callback in order to calculate the optimal amount of nodes
  to use for running a `LiveLoad.Scenario` based on the number of users for the test and the resources available on each
  cluster node.
  """
  @callback browser_contexts_per_core() :: pos_integer()

  @doc """
  Different browser implementations may have different memory requirements, depending on how they are implemented.
  The `LiveLoad.Cluster` initialization procedure uses this callback in order to calculate the optimal amount of nodes
  to use for running a `LiveLoad.Scenario` based on the number of users for the test and the resources available on each
  cluster node.
  """
  @callback browser_memory_usage_bytes() :: pos_integer()

  @doc """
  Different browser implementations may have different memory requirements, depending on how they are implemented.
  The `LiveLoad.Cluster` initialization procedure uses this callback in order to calculate the optimal amount of nodes
  to use for running a `LiveLoad.Scenario` based on the number of users for the test and the resources available on each
  cluster node.
  """
  @callback context_memory_usage_bytes() :: pos_integer()

  #############################
  ##### Process Callbacks #####
  #############################
  @callback child_spec(opts :: opts()) :: Supervisor.child_spec()

  @doc """
  Any connection can broadcast telemetry events that correspond to load test metrics which `LiveLoad` tracks during a scenario.
  Since connections are generally modeled around Ports, the telemetry sent by those ports may be asynchronous in nature,
  meaning that stopping a context does not necessarily mean that all metrics have completed sending and been consumed.
  To avoid race conditions and dropping metrics, this callback can be implemented by a connection's metrics collection mechanism
  to ensure that all metrics have been sent and drained.

  A reference implementation can be found in the `LiveLoad.Browser.Connection.Playwright` implementation of the connection behaviour.
  """
  @callback drain_metrics(browser :: Browser.t()) :: :ok

  #############################
  ##### Browser Callbacks #####
  #############################
  @callback new_context(browser :: Browser.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback stop_context(context :: Context.t()) :: :ok | {:error, term()}

  # Storage

  @typedoc """
  A serializable storage snapshot that contains the current browser context's cookies, local storage, and session storage.

  This type is intentionally left as an ambiguous term, as it is meant to be usable as a storage and restoration mechanism,
  however it is not guaranteed to be uniform across different browser connections.
  """
  @type context_storage_snapshot() :: term()

  @callback context_storage_snapshot(context :: Context.t()) ::
              {:ok, {Context.t(), context_storage_snapshot()}} | {:error, term()}
  @callback restore_context_storage(context :: Context.t(), snapshot :: context_storage_snapshot()) ::
              {:ok, Context.t()} | {:error, term()}
  @callback reset_context_storage(context :: Context.t()) :: {:ok, Context.t()} | {:error, term()}

  # Navigation

  @callback navigate(context :: Context.t(), url :: String.t() | URI.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback reload(context :: Context.t()) :: {:ok, Context.t()} | {:error, term()}

  # User/Browser Operations

  @callback wait_for_selector(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback click(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback fill(context :: Context.t(), selector :: String.t(), value :: String.t()) ::
              {:ok, Context.t()} | {:error, term()}
  @callback press(context :: Context.t(), selector :: String.t(), key :: String.t()) ::
              {:ok, Context.t()} | {:error, term()}
  @callback check(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback uncheck(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback select_option(context :: Context.t(), selector :: String.t(), value :: String.t()) ::
              {:ok, Context.t()} | {:error, term()}
  @callback select_multiple_options(context :: Context.t(), selector :: String.t(), values :: [String.t()]) ::
              {:ok, Context.t()} | {:error, term()}
  @callback focus(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback blur(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback hover(context :: Context.t(), selector :: String.t()) :: {:ok, Context.t()} | {:error, term()}
  @callback drag_and_drop(context :: Context.t(), source :: String.t(), target :: String.t()) ::
              {:ok, Context.t()} | {:error, term()}

  # Reading Values

  @callback page_content(context :: Context.t()) :: {:ok, {Context.t(), String.t()}} | {:error, term()}
  @callback inner_html(context :: Context.t(), selector :: String.t()) ::
              {:ok, {Context.t(), String.t()}} | {:error, term()}
  @callback inner_text(context :: Context.t(), selector :: String.t()) ::
              {:ok, {Context.t(), String.t()}} | {:error, term()}
  @callback text_content(context :: Context.t(), selector :: String.t()) ::
              {:ok, {Context.t(), String.t() | nil}} | {:error, term()}
  @callback input_value(context :: Context.t(), selector :: String.t()) ::
              {:ok, {Context.t(), String.t()}} | {:error, term()}
  @callback get_attribute(context :: Context.t(), selector :: String.t(), name :: String.t()) ::
              {:ok, {Context.t(), String.t() | nil}} | {:error, term()}
  @callback visible?(context :: Context.t(), selector :: String.t()) ::
              {:ok, {Context.t(), boolean()}} | {:error, term()}
  @callback checked?(context :: Context.t(), selector :: String.t()) ::
              {:ok, {Context.t(), boolean()}} | {:error, term()}

  ##############################
  ## Lifecycle Hook Callbacks ##
  ##############################

  @doc "A hook called before the supervision tree for the browser is initialized."
  @callback before_start(browser :: Browser.t()) :: {:ok, Browser.t()} | {:error, term()}

  @doc "A hook called after the supervision tree for the browser is initialized."
  @callback after_start(browser :: Browser.t()) :: {:ok, Browser.t()} | {:error, term()}

  @doc """
  A hook called before the supervision tree for the browser is stopped.

  This hook is meant for side effects and as such cannot return any value other than `:ok`
  """
  @callback before_stop(browser :: Browser.t()) :: :ok

  @doc """
  A hook called after the supervision tree for the browser is stopped.

  This hook is meant for side effects and as such cannot return any value other than `:ok`
  """
  @callback after_stop(browser :: Browser.t()) :: :ok

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour LiveLoad.Browser.Connection

      @doc false
      def child_spec(_opts), do: %{id: __MODULE__, start: {Function, :identity, [:ignore]}, restart: :temporary}
      defoverridable child_spec: 1

      @doc false
      def drain_metrics(browser), do: :ok
      defoverridable drain_metrics: 1

      @doc false
      def metadata, do: %{adapter: inspect(__MODULE__), unsupported_metrics: %{}, unsupported_features: %{}}
      defoverridable metadata: 0

      @doc false
      def before_start(browser), do: {:ok, browser}
      defoverridable before_start: 1

      @doc false
      def after_start(browser), do: {:ok, browser}
      defoverridable after_start: 1

      @doc false
      def before_stop(browser), do: :ok
      defoverridable before_stop: 1

      @doc false
      def after_stop(browser), do: :ok
      defoverridable after_stop: 1
    end
  end
end
