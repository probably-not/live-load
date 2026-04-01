defmodule LiveLoad.Scenario.Example do
  @moduledoc false
  use LiveLoad.Scenario

  @impl true
  def config(opts) do
    {:ok, Map.new(opts)}
  end

  @impl true
  def run(%LiveLoad.Scenario.Context{} = context, _user_id, _config) do
    context
    |> navigate("https://app.marketeam.ai")
    |> ensure_liveview()
    |> wait_for_liveview()
    |> tap(fn _ -> Process.sleep(to_timeout(second: Enum.random(1..20))) end)
    |> page_content()
    |> tap(fn _ -> Process.sleep(to_timeout(second: Enum.random(1..20))) end)
    |> inner_html("body", as: :body)
    |> tap(fn _ -> Process.sleep(to_timeout(second: Enum.random(1..20))) end)
    |> inner_html("a", as: fn _ -> :a end)
    |> tap(fn _ -> Process.sleep(to_timeout(second: Enum.random(1..20))) end)
    |> inner_html("div", as: fn _ -> %{div: "a", div2: "b"} end)
    |> tap(fn _ -> Process.sleep(to_timeout(second: Enum.random(1..20))) end)

    :ok
  end
end
