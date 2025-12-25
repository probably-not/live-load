defmodule LiveLoad.Browser.Connection.Playwright.Decompressor do
  @moduledoc false

  def extract!(version) when is_binary(version) do
    version
    |> Version.parse!()
    |> Version.to_string()
    |> do_extract()
  end

  def extract!(%Version{} = version) do
    version
    |> Version.to_string()
    |> do_extract()
  end

  defp do_extract(version) when is_binary(version) do
    archive = Application.app_dir(:live_load, ["priv", "playwright", version, "playwright_bundle.tar.gz"])
    dest = Application.app_dir(:live_load, ["priv", "playwright", version, "bin"])
    File.rm_rf!(dest)
    File.mkdir_p!(dest)
    :ok = :erl_tar.extract(String.to_charlist(archive), [:compressed, {:cwd, String.to_charlist(dest)}])
    Path.join(dest, "assets/node_modules/playwright/cli.js")
  end
end
