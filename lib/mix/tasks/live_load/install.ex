defmodule Mix.Tasks.LiveLoad.Install do
  @shortdoc "Downloads and installs the necessary Playwright driver and browser binaries for LiveLoad"

  @moduledoc """
  Downloads and installs the necessary Playwright driver and browser binaries for `LiveLoad`.

  Playwright's installations are per platform and architecture, so for `LiveLoad` to properly run on a production environment,
  the `mix live_load.install` command should run on the final environment in order to download the correct binaries (for example,
  during your build process). The installation files will be installed into the `priv` directory for the `live_load` application
  and will be packaged during the build to be available in the running application.

  This must be run with the version of Playwright that is going to be used.
  The default version is #{LiveLoad.Browser.Connection.Playwright.Supervisor.playwright_version_from_env()}.


  ## Examples

      $ mix live_load.install
      $ mix live_load.install 1.62.0
  """
  use Mix.Task

  @base_url URI.new!("https://playwright.azureedge.net/builds/driver")

  @doc false
  def run([]) do
    default_version = LiveLoad.Browser.Connection.Playwright.Supervisor.playwright_version_from_env()
    run([default_version])
  end

  def run([version]) do
    Application.ensure_all_started([:inets, :ssl])

    platform = platform()

    priv_dir = Application.app_dir(:live_load, ["priv", "playwright"])
    File.mkdir_p!(priv_dir)

    versioned_path = Path.join(priv_dir, version)
    driver_dir = Path.join(versioned_path, "driver")
    browsers_dir = Path.join(versioned_path, "browsers")

    File.mkdir_p!(driver_dir)
    File.mkdir_p!(browsers_dir)

    zip_url =
      @base_url
      |> URI.append_path("/playwright-#{version}-#{platform}.zip")
      |> URI.to_string()

    zip_path = Path.join(versioned_path, "playwright-driver.zip")

    Mix.shell().info("Downloading Playwright driver #{version} for #{platform}")

    :ok = :public_key.cacerts_load()

    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    body =
      case :httpc.request(:get, {String.to_charlist(zip_url), []}, [ssl: ssl_opts], body_format: :binary) do
        {:ok, {{_, 200, _}, _, body}} ->
          body

        {:ok, {{_, status, _}, _, _}} ->
          Mix.raise("Failed to download Playwright driver #{version} for #{platform}: HTTP #{status} from #{zip_url}")

        {:error, reason} ->
          Mix.raise("Failed to download Playwright driver #{version} for #{platform}: #{inspect(reason)}")
      end

    File.write!(zip_path, body)

    {:ok, _} = :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(driver_dir))
    File.rm!(zip_path)

    node_path = Path.join(driver_dir, "node")
    File.chmod!(node_path, 0o755)

    wrapper_path = Path.join(driver_dir, "playwright-driver")

    File.write!(wrapper_path, """
    #!/bin/sh
    exec "$(dirname "$0")/node" "$(dirname "$0")/package/cli.js" "$@"
    """)

    File.chmod!(wrapper_path, 0o755)

    cli_path = Path.join([driver_dir, "package", "cli.js"])

    Mix.shell().info("Installing Chromium")

    chromium_install_result =
      System.cmd(Path.expand(node_path), [Path.expand(cli_path), "install", "chromium"],
        env: [{"PLAYWRIGHT_BROWSERS_PATH", Path.expand(browsers_dir)}],
        into: IO.stream(:stdio, :line)
      )

    case chromium_install_result do
      {_, 0} -> :ok
      {_, code} -> Mix.raise("Playwright Chromium installation failed with exit code #{code}")
    end

    archive_path = Path.join(versioned_path, "playwright_bundle.tar.gz")

    :ok =
      :erl_tar.create(
        String.to_charlist(archive_path),
        [
          {~c"driver", String.to_charlist(driver_dir)},
          {~c"browsers", String.to_charlist(browsers_dir)}
        ],
        [:compressed]
      )

    File.rm_rf!(driver_dir)
    File.rm_rf!(browsers_dir)

    Mix.shell().info("Compressed playwright to #{archive_path}")
  end

  # credo:disable-for-lines:14 Credo.Check.Refactor.CyclomaticComplexity
  defp platform do
    {_, os_name} = :os.type()
    arch = to_string(:erlang.system_info(:system_architecture))

    cond do
      os_name == :darwin and arch =~ "aarch64" -> "mac-arm64"
      os_name == :darwin and arch =~ "arm" -> "mac-arm64"
      os_name == :darwin -> "mac"
      os_name == :linux and arch =~ "aarch64" -> "linux-arm64"
      os_name == :linux and arch =~ "arm" -> "linux-arm64"
      os_name == :linux -> "linux"
      true -> "win32_x64"
    end
  end
end
