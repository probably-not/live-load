defmodule LiveLoad.Scenario.Example do
  @moduledoc false
  use LiveLoad.Scenario

  @impl true
  def config(opts) do
    {:ok, Map.new(opts)}
  end

  @impl true
  def run(%LiveLoad.Scenario.Context{} = context, user_id, _config) do
    context
    |> navigate("https://app.marketeam.ai")
    |> wait_for_selector(".phx-connected")

    # credo:disable-for-next-line
    dbg({user_id, context})
    :ok
  end
end
