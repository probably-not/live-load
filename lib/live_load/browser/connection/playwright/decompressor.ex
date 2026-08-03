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
    base_path = Application.app_dir(:live_load, ["priv", "playwright", version])

    dest = Path.join(base_path, "bin")
    cli_path = Path.join(dest, "driver/playwright-driver")

    if File.exists?(cli_path) do
      cli_path
    else
      archive = Path.join(base_path, "playwright_bundle.tar.gz")

      if not File.exists?(archive) do
        raise RuntimeError, """
        The Playwright bundle does not currently exist.

        In order to install Playwright, run `mix live_load.install` to install the default version.
        """
      end

      File.rm_rf!(dest)
      File.mkdir_p!(dest)
      :ok = :erl_tar.extract(String.to_charlist(archive), [:compressed, {:cwd, String.to_charlist(dest)}])
      cli_path
    end
  end
end
