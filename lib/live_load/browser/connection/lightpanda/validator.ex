defmodule LiveLoad.Browser.Connection.Lightpanda.Validator do
  @moduledoc false

  def validate!("nightly") do
    do_validate("nightly")
  end

  def validate!(version) when is_binary(version) do
    version
    |> Version.parse!()
    |> Version.to_string()
    |> do_validate()
  end

  def validate!(%Version{} = version) do
    version
    |> Version.to_string()
    |> do_validate()
  end

  defp do_validate(version) when is_binary(version) do
    base_path = Application.app_dir(:live_load, ["priv", "lightpanda", version])
    bin_path = Path.join(base_path, "lightpanda")

    if not File.exists?(bin_path) do
      raise RuntimeError, """
      The Lightpanda binary does not currently exist.

      In order to install Lightpanda, run `mix live_load.install.lightpanda` to install the default version.
      """
    end

    ensure_executable!(bin_path)
    bin_path
  end

  defp ensure_executable!(bin_path) do
    case System.cmd(bin_path, ["version"]) do
      {_, 0} ->
        :ok

      {output, code} ->
        raise """
        The Lightpanda binary is not executable (code: #{code}).

        In order to install Lightpanda, run `mix live_load.install.lightpanda` to install the default version.

        If you are installing Lightpanda separately, make sure that the path to Lightpanda that is passed in to LiveLoad
        is a file that is executable by the current application.

        Command output:

        #{output}
        """
    end
  end
end
