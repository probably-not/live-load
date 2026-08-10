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

  ## Options

    * `--no-bundle` - does not bundle and compress the Playwright driver and browser.
      Leaving the driver and browser compressed means that when running a load test,
      the startup time pays a cost for unpacking the archive. Depending on the size of
      the load test, this may take a while, as each node needs to unpack and then set up
      the browser. Using this flag will leave the Playwright driver and browser unbundled,
      which may result in a higher release bundle as a tradeoff.


  ## Examples

      $ mix live_load.install
      $ mix live_load.install --no-bundle
      $ mix live_load.install 1.62.0
      $ mix live_load.install 1.62.0 --no-bundle
  """
  use Mix.Task

  # Playwright's old azureedge endpoints are now returning 404 for the newer builds.
  # Looks like it's a necessary evil to install and run things via a shimmed node local for Playwright.
  # This is pretty close to what others are doing in their Playwright forks, so I'm going to keep this here
  # so that people can still avoid needing to know anything about node for using LiveLoad.
  @npm_registry URI.new!("https://registry.npmjs.org")
  @nodejs_dist URI.new!("https://nodejs.org/dist")
  @nodejs_version "24.18.0"

  @switches [no_bundle: :boolean]

  @doc false
  def run(args) do
    {opts, argv} = OptionParser.parse!(args, strict: @switches)
    version = version!(argv)

    Application.ensure_all_started([:inets, :ssl])

    priv_dir = Application.app_dir(:live_load, ["priv", "playwright"])
    File.mkdir_p!(priv_dir)

    versioned_path = Path.join(priv_dir, version)
    driver_dir = Path.join(versioned_path, "driver")
    browsers_dir = Path.join(versioned_path, "browsers")

    File.mkdir_p!(driver_dir)
    File.mkdir_p!(browsers_dir)

    install_driver!(driver_dir, version)
    install_browsers!(driver_dir, browsers_dir)

    if Keyword.get(opts, :no_bundle, false) do
      no_bundle!(versioned_path, driver_dir, browsers_dir)
    else
      bundle!(versioned_path, driver_dir, browsers_dir)
    end
  end

  defp version!([]), do: LiveLoad.Browser.Connection.Playwright.Supervisor.playwright_version_from_env()
  defp version!([version]), do: version

  defp version!(argv) do
    Mix.raise("Expected a single Playwright version, got: #{Enum.join(argv, ", ")}")
  end

  defp install_driver!(driver_dir, version) do
    Mix.shell().info("Downloading Playwright driver #{version}")

    url =
      @npm_registry
      |> URI.append_path("/playwright-core/-/playwright-core-#{version}.tgz")
      |> URI.to_string()

    body = download!(url, "Playwright driver #{version}")
    :ok = :erl_tar.extract({:binary, body}, [:compressed, {:cwd, String.to_charlist(driver_dir)}])

    install_nodejs!(driver_dir)
    write_wrapper!(driver_dir)
  end

  defp install_nodejs!(driver_dir) do
    platform = nodejs_platform()
    archive = "node-v#{@nodejs_version}-#{platform}"

    Mix.shell().info("Downloading Node.js #{@nodejs_version} for #{platform}")

    url =
      @nodejs_dist
      |> URI.append_path("/v#{@nodejs_version}/#{archive}.tar.gz")
      |> URI.to_string()

    body = download!(url, "Node.js #{@nodejs_version} for #{platform}")

    tmp_dir = Path.join(driver_dir, "_node")
    File.mkdir_p!(tmp_dir)

    :ok =
      :erl_tar.extract({:binary, body}, [
        :compressed,
        {:cwd, String.to_charlist(tmp_dir)},
        {:files, [String.to_charlist("#{archive}/bin/node")]}
      ])

    node_path = Path.join(driver_dir, "node")
    File.rename!(Path.join([tmp_dir, archive, "bin", "node"]), node_path)
    File.chmod!(node_path, 0o755)
    File.rm_rf!(tmp_dir)
  end

  defp write_wrapper!(driver_dir) do
    wrapper_path = Path.join(driver_dir, "playwright-driver")

    File.write!(wrapper_path, """
    #!/bin/sh
    exec "$(dirname "$0")/node" "$(dirname "$0")/package/cli.js" "$@"
    """)

    File.chmod!(wrapper_path, 0o755)
  end

  defp install_browsers!(driver_dir, browsers_dir) do
    node_path = Path.join(driver_dir, "node")
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
  end

  defp bundle!(versioned_path, driver_dir, browsers_dir) do
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
    File.rm_rf!(bin_dir(versioned_path))

    Mix.shell().info("Compressed playwright to #{archive_path}")
  end

  defp no_bundle!(versioned_path, driver_dir, browsers_dir) do
    bin_dir = bin_dir(versioned_path)
    File.rm_rf!(bin_dir)
    File.mkdir_p!(bin_dir)

    File.rename!(driver_dir, Path.join(bin_dir, "driver"))
    File.rename!(browsers_dir, Path.join(bin_dir, "browsers"))
    File.rm_rf!(Path.join(versioned_path, "playwright_bundle.tar.gz"))

    Mix.shell().info("Decompressed playwright to #{bin_dir}")
  end

  defp bin_dir(versioned_path), do: Path.join(versioned_path, "bin")

  defp download!(url, description) do
    :ok = :public_key.cacerts_load()

    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl_opts], body_format: :binary) do
      {:ok, {{_, 200, _}, _, body}} ->
        body

      {:ok, {{_, status, _}, _, _}} ->
        Mix.raise("Failed to download #{description}: HTTP #{status} from #{url}")

      {:error, reason} ->
        Mix.raise("Failed to download #{description}: #{inspect(reason)}")
    end
  end

  defp nodejs_platform do
    arch = to_string(:erlang.system_info(:system_architecture))

    cpu =
      cond do
        arch =~ "aarch64" -> "arm64"
        arch =~ "arm" -> "arm64"
        true -> "x64"
      end

    case :os.type() do
      {:unix, :darwin} -> "darwin-#{cpu}"
      {:unix, :linux} -> "linux-#{cpu}"
      {family, name} -> Mix.raise("Unsupported platform: #{family}/#{name}")
    end
  end
end
