defmodule LiveLoad.Scenario.Example do
  @moduledoc false
  use LiveLoad.Scenario

  @impl true
  def run(_user_id, _config) do
    # dbg(user_id)
    # dbg(config)
    # dbg(node())

    Process.sleep(60_000)
    :ok
  end
end
