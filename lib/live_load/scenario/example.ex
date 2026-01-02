defmodule LiveLoad.Scenario.Example do
  @moduledoc false
  use LiveLoad.Scenario

  @impl true
  def config(opts) do
    {:ok, Map.new(opts)}
  end

  @impl true
  def run(user_id, config) do
    # credo:disable-for-next-line
    dbg(user_id)
    # credo:disable-for-next-line
    dbg(config)
    # credo:disable-for-next-line
    dbg(node())

    Process.sleep(60_000)
    :ok
  end
end
