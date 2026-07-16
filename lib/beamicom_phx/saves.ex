defmodule BeamicomPhx.Saves do
  @moduledoc """
  On-disk gallery of save-state share PNGs, served straight from
  `priv/static/saves` (whitelisted in `BeamicomPhxWeb.static_paths/0`).

  Saves are global, matching the single shared emulator: capturing broadcasts on
  the `"saves"` PubSub topic so every connected `WatchLive` refreshes its grid.
  """

  alias Beamicom.NES.{Runtime, ShareImage}

  @topic "saves"

  @doc "Directory holding the save PNGs (served at /saves/<file>)."
  def dir, do: Path.join(:code.priv_dir(:beamicom_phx), "static/saves")

  @doc "Subscribe the caller to gallery-change notifications."
  def subscribe, do: Phoenix.PubSub.subscribe(BeamicomPhx.PubSub, @topic)

  @doc "URLs of every save, newest first."
  def list do
    case File.ls(dir()) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".png"))
        |> Enum.sort(:desc)
        |> Enum.map(&("/saves/" <> &1))

      {:error, _} ->
        []
    end
  end

  @doc """
  Snapshot the running emulator and write a new save PNG. Broadcasts on success.
  Returns `{:ok, url}` or `{:error, reason}`.
  """
  def capture do
    if BeamicomPhx.Emulator.loaded?() do
      case Runtime.snapshot() do
        {console, frame} when not is_nil(frame) ->
          File.mkdir_p!(dir())
          name = "save-#{System.system_time(:millisecond)}.png"
          File.write!(Path.join(dir(), name), ShareImage.to_png(console, frame))
          Phoenix.PubSub.broadcast(BeamicomPhx.PubSub, @topic, :saves_changed)
          {:ok, "/saves/" <> name}

        _ ->
          {:error, :no_frame}
      end
    else
      {:error, :not_loaded}
    end
  end

  @doc "Load a save (by URL or basename) into the running emulator."
  def load(url) do
    path = Path.join(dir(), Path.basename(url))

    with {:ok, png} <- File.read(path),
         {:ok, console} <- ShareImage.load_image(png, []) do
      BeamicomPhx.Emulator.load_console(console)
    end
  end
end
