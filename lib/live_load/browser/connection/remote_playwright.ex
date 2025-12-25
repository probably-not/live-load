defmodule LiveLoad.Browser.Connection.RemotePlaywright do
  @moduledoc false

  @behaviour LiveLoad.Browser.Connection

  @impl LiveLoad.Browser.Connection
  def start_link(_opts) do
    {:error, :not_implemented_yet}
  end
end
