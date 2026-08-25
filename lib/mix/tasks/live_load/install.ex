defmodule Mix.Tasks.LiveLoad.Install do
  @shortdoc "Shortcut for the `mix live_load.install.playwright` kept as backwards compatibility."

  @moduledoc """
  Downloads and installs the necessary Playwright driver and browser binaries for `LiveLoad`.

  This is a shortcut to the `mix live_load.install.playwright` Mix Task, which should be used going forward.
  See that mix task for the documentation.

  > ### Deprecation Notice {: .warning}
  >
  > When writing the first version of LiveLoad, I set up this install task
  > to install Playwright automatically for the user. However, now that I'm
  > expanding LiveLoad's capabilities to include things like a Lightpanda
  > browser implementation, `live_load.install` feels like the wrong name for
  > installing the Playwright browser files necessary to run... so I decided
  > to make a more specific name for that Mix Task. I'm leaving this one here
  > as backwards compatibility, it will simply call that Mix Task directly.
  > This Mix Task will eventually be removed, so anyone using it should migrate
  > to the new, specific Mix Task moving forward.
  """
  use Mix.Task

  @doc false
  def run(args) do
    Mix.Tasks.LiveLoad.Install.Playwright.run(args)
  end
end
