defmodule LiveLoad.Scenario.Example do
  @moduledoc false
  use LiveLoad.Scenario

  alias LiveLoad.Scenario.Throttle.Rate

  @impl true
  def config(opts) do
    {:ok, Map.new(opts)}
  end

  @impl true
  def run(%LiveLoad.Scenario.Context{} = context, _user_id, _config) do
    context
    |> throttle(:visitors)
    |> navigate("https://live-load-bench.fly.dev/")
    |> ensure_liveview()
    |> wait_for_liveview()
    |> page_content()
    |> inner_html("body", as: :body)
    |> inner_html("a", as: fn _ -> :a end)
    |> inner_html("div", as: fn _ -> %{div: "a", div2: "b"} end)
  end

  @impl true
  def throttles(_config) do
    [
      :visitors
      |> Rate.new(1)
      |> Rate.ramp(100, duration: to_timeout(second: 5))
    ]
  end
end
