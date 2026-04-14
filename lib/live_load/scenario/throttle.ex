defprotocol LiveLoad.Scenario.Throttle do
  @moduledoc false

  @spec name(t()) :: atom()
  def name(throttle)

  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(throttle)

  @spec to_amoc_config(t) :: :amoc_throttle.t()
  def to_amoc_config(throttle)

  @spec to_amoc_gradual_plan(t) :: :amoc_throttle.gradual_plan() | nil
  def to_amoc_gradual_plan(throttle)
end
