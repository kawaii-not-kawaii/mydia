defmodule MydiaWeb.MusicLive.Show do
  use MydiaWeb, :live_view

  alias Mydia.Music

  import MydiaWeb.PlaylistComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    album =
      Music.get_album!(id,
        preload: [:artist, tracks: [:artist, :music_files]]
      )

    user = socket.assigns.current_scope.user
    playlists = Music.list_user_playlists(user.id)

    {:noreply,
     socket
     |> assign(:page_title, album.title)
     |> assign(:album, album)
     |> assign(:playlists, playlists)
     |> assign(:show_create_playlist_modal, false)
     |> assign(:pending_track_id, nil)
     |> assign(:pending_album_id, nil)
     |> assign(:form, to_form(Music.change_playlist(%Music.Playlist{})))}
  end

  @impl true
  def handle_event("toggle_monitored", _params, socket) do
    album = socket.assigns.album
    new_monitored_status = !album.monitored

    case Music.update_album(album, %{monitored: new_monitored_status}) do
      {:ok, updated_album} ->
        {:noreply,
         socket
         |> assign(:album, %{socket.assigns.album | monitored: updated_album.monitored})
         |> put_flash(
           :info,
           "Monitoring #{if new_monitored_status, do: "enabled", else: "disabled"}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update monitoring status")}
    end
  end

  # Playlist events
  def handle_event(
        "add_to_playlist",
        %{"playlist-id" => playlist_id, "album-id" => album_id},
        socket
      )
      when is_binary(album_id) and album_id != "" do
    playlist = Music.get_playlist!(playlist_id)
    album = socket.assigns.album
    tracks = Enum.sort_by(album.tracks, &{&1.disc_number, &1.track_number})

    {:ok, _} = Music.add_tracks_to_playlist(playlist, tracks)
    {:noreply, put_flash(socket, :info, "Album added to #{playlist.name}")}
  end

  def handle_event(
        "add_to_playlist",
        %{"playlist-id" => playlist_id, "track-id" => track_id},
        socket
      )
      when is_binary(track_id) and track_id != "" do
    playlist = Music.get_playlist!(playlist_id)
    track = Music.get_track!(track_id)

    case Music.add_track_to_playlist(playlist, track) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Track added to #{playlist.name}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add track to playlist")}
    end
  end

  def handle_event("create_playlist_for_track", %{"album-id" => album_id}, socket)
      when is_binary(album_id) and album_id != "" do
    {:noreply,
     socket
     |> assign(:show_create_playlist_modal, true)
     |> assign(:pending_album_id, album_id)
     |> assign(:pending_track_id, nil)}
  end

  def handle_event("create_playlist_for_track", %{"track-id" => track_id}, socket)
      when is_binary(track_id) and track_id != "" do
    {:noreply,
     socket
     |> assign(:show_create_playlist_modal, true)
     |> assign(:pending_track_id, track_id)
     |> assign(:pending_album_id, nil)}
  end

  def handle_event("create_playlist_for_track", _params, socket) do
    {:noreply, assign(socket, :show_create_playlist_modal, true)}
  end

  def handle_event("close_create_playlist_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_playlist_modal, false)
     |> assign(:pending_track_id, nil)
     |> assign(:pending_album_id, nil)
     |> assign(:form, to_form(Music.change_playlist(%Music.Playlist{})))}
  end

  def handle_event("validate_playlist", %{"playlist" => params}, socket) do
    form =
      %Music.Playlist{}
      |> Music.change_playlist(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("create_playlist", %{"playlist" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Music.create_playlist(user, params) do
      {:ok, playlist} ->
        # Add the pending track/album if any
        socket =
          cond do
            socket.assigns.pending_album_id ->
              album = socket.assigns.album
              tracks = Enum.sort_by(album.tracks, &{&1.disc_number, &1.track_number})
              Music.add_tracks_to_playlist(playlist, tracks)
              put_flash(socket, :info, "Playlist created and album added")

            socket.assigns.pending_track_id ->
              track = Music.get_track!(socket.assigns.pending_track_id)
              Music.add_track_to_playlist(playlist, track)
              put_flash(socket, :info, "Playlist created and track added")

            true ->
              put_flash(socket, :info, "Playlist created")
          end

        playlists = Music.list_user_playlists(user.id)

        {:noreply,
         socket
         |> assign(:playlists, playlists)
         |> assign(:show_create_playlist_modal, false)
         |> assign(:pending_track_id, nil)
         |> assign(:pending_album_id, nil)
         |> assign(:form, to_form(Music.change_playlist(%Music.Playlist{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp get_cover_url(album) do
    if is_binary(album.cover_url) and album.cover_url != "" do
      album.cover_url
    else
      "/images/no-poster.svg"
    end
  end

  defp format_year(nil), do: "N/A"
  defp format_year(%Date{year: year}), do: year
  defp format_year(year), do: year

  defp format_track_duration(nil), do: "-"

  defp format_track_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(to_string(remaining_seconds), 2, "0")}"
  end

  defp get_total_duration(album) do
    case album.total_duration do
      duration when is_integer(duration) and duration > 0 ->
        duration

      _ ->
        album.tracks
        |> Enum.map(& &1.duration)
        |> Enum.reject(&is_nil/1)
        |> Enum.sum()
    end
  end

  defp format_total_duration(seconds) when is_integer(seconds) and seconds > 0 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if hours > 0 do
      "#{hours}h #{minutes}m"
    else
      "#{minutes} min"
    end
  end

  defp format_total_duration(_), do: "-"

  defp total_file_size(album) do
    album.tracks
    |> Enum.flat_map(fn track ->
      case track.music_files do
        files when is_list(files) -> files
        _ -> []
      end
    end)
    |> Enum.map(& &1.size)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp format_file_size(0), do: "-"
  defp format_file_size(nil), do: "-"

  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp get_album_type_label(album_type) do
    case album_type do
      "album" -> "Album"
      "single" -> "Single"
      "ep" -> "EP"
      "compilation" -> "Compilation"
      _ -> "Album"
    end
  end

  defp track_has_file?(track) do
    case track.music_files do
      files when is_list(files) and files != [] -> true
      _ -> false
    end
  end
end
