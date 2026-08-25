defmodule Mix.Tasks.LiveLoad.Install.Lightpanda do
  @shortdoc "Downloads and installs the necessary Lightpanda browser binary for LiveLoad"

  @moduledoc """
  Downloads and installs the necessary Lightpanda browser binary for `LiveLoad`.

  Lightpanda's installations are per platform and architecture, so for `LiveLoad` to properly run on a production environment,
  the `mix live_load.install.lightpanda` command should run on the final environment in order to download the correct binary (for example,
  during your build process). The browser binary will be installed into the `priv` directory for the `live_load` application
  and will be packaged during the build to be available in the running application.

  This must be run with the version of Lightpanda that is going to be used.
  The default version is #{LiveLoad.Browser.Connection.Lightpanda.Supervisor.lightpanda_version_from_env()}.
  Versions correspond to GitHub releases, so any matching version will be downloaded.

  ## Examples

      $ mix live_load.install.lightpanda
      $ mix live_load.install.lightpanda
      $ mix live_load.install.lightpanda 0.3.6
      $ mix live_load.install.lightpanda nightly
  """
  use Mix.Task

  @lightpanda_releases URI.new!("https://github.com/lightpanda-io/browser/releases/download")

  @doc false
  def run(args) do
    {_opts, argv} = OptionParser.parse!(args, switches: [])
    version = version!(argv)

    Application.ensure_all_started([:inets, :ssl])

    priv_dir = Application.app_dir(:live_load, ["priv", "lightpanda"])
    File.mkdir_p!(priv_dir)

    versioned_path = Path.join(priv_dir, version)
    File.mkdir_p!(versioned_path)

    bin_path = Path.join(versioned_path, "lightpanda")
    platform = lightpanda_platform!()

    Mix.shell().info("Downloading Lightpanda #{version} for #{platform}")

    url =
      @lightpanda_releases
      |> URI.append_path("/#{version}/lightpanda-#{platform}")
      |> URI.to_string()

    File.write!(bin_path, download!(url, "Lightpanda #{version} for #{platform}"))
    File.chmod!(bin_path, 0o755)
  end

  defp version!([]), do: LiveLoad.Browser.Connection.Lightpanda.Supervisor.lightpanda_version_from_env()
  defp version!([version]), do: version

  defp version!(argv) do
    Mix.raise("Expected a single Lightpanda version, got: #{Enum.join(argv, ", ")}")
  end

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

  defp lightpanda_platform! do
    arch = to_string(:erlang.system_info(:system_architecture))

    cpu =
      cond do
        arch =~ "aarch64" -> "aarch64"
        arch =~ "arm" -> "aarch64"
        true -> "x86_64"
      end

    case :os.type() do
      {:unix, :darwin} -> "#{cpu}-macos"
      {:unix, :linux} -> "#{cpu}-linux"
      {family, name} -> Mix.raise("Unsupported Lightpanda platform: #{family}/#{name}")
    end
  end
end
