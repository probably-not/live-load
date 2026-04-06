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
    |> page_content()
    |> inner_html("body", as: :body)
    |> inner_html("a", as: fn _ -> :a end)
    |> inner_html("div", as: fn _ -> %{div: "a", div2: "b"} end)
  end
end
