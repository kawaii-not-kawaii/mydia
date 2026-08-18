defmodule MydiaWeb.MusicLive.PlaylistShow do
  use MydiaWeb, :live_view

  alias Mydia.Music

  import MydiaWeb.PlaylistComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    playlist = Music.get_playlist_with_tracks!(id)

    {:noreply,
     socket
     |> assign(:page_title, playlist.name)
     |> assign(:playlist, playlist)
     |> assign(:show_edit_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:form, to_form(Music.change_playlist(playlist)))}
  end

  @impl true
  def handle_event("remove_track", %{"playlist-track-id" => playlist_track_id}, socket) do
    playlist_track = Music.get_playlist_track!(playlist_track_id)

    case Music.remove_track_from_playlist(playlist_track) do
      {:ok, _} ->
        playlist = Music.get_playlist_with_tracks!(socket.assigns.playlist.id)

        {:noreply,
         socket
         |> assign(:playlist, playlist)
         |> put_flash(:info, "Track removed from playlist")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove track")}
    end
  end

  def handle_event("edit_playlist", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, true)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:form, to_form(Music.change_playlist(socket.assigns.playlist)))}
  end

  def handle_event("validate", %{"playlist" => params}, socket) do
    form =
      socket.assigns.playlist
      |> Music.change_playlist(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("update_playlist", %{"playlist" => params}, socket) do
    case Music.update_playlist(socket.assigns.playlist, params) do
      {:ok, playlist} ->
        {:noreply,
         socket
         |> assign(:playlist, %{
           socket.assigns.playlist
           | name: playlist.name,
             description: playlist.description
         })
         |> assign(:page_title, playlist.name)
         |> assign(:show_edit_modal, false)
         |> put_flash(:info, "Playlist updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete_playlist", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("confirm_delete", _params, socket) do
    case Music.delete_playlist(socket.assigns.playlist) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Playlist deleted")
         |> push_navigate(to: ~p"/music/playlists")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:show_delete_modal, false)
         |> put_flash(:error, "Failed to delete playlist")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col h-full">
        <%!-- Back button --%>
        <div class="mb-6">
          <.link navigate={~p"/music/playlists"} class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Playlists
          </.link>
        </div>

        <%!-- Playlist header --%>
        <.playlist_header playlist={@playlist} />

        <%!-- Track listing --%>
        <%= if @playlist.playlist_tracks == [] do %>
          <div class="flex flex-col items-center justify-center py-16 bg-base-100 rounded-lg">
            <.icon name="hero-musical-note" class="w-12 h-12 text-base-content/20 mb-4" />
            <h2 class="text-lg font-semibold mb-2">This playlist is empty</h2>
            <p class="text-base-content/60 mb-4">Add tracks from albums or the music library</p>
            <.link navigate={~p"/music"} class="btn btn-primary gap-2">
              <.icon name="hero-musical-note" class="w-5 h-5" /> Browse Music
            </.link>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-0">
              <div class="overflow-x-auto">
                <table class="table" id="playlist-tracks">
                  <thead>
                    <tr>
                      <th class="w-12">#</th>
                      <th>Title</th>
                      <th class="hidden sm:table-cell">Album</th>
                      <th class="w-20 text-right">Duration</th>
                      <th class="w-12"></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for {playlist_track, index} <- Enum.with_index(@playlist.playlist_tracks, 1) do %>
                      <.playlist_track_row playlist_track={playlist_track} index={index} />
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Edit Modal --%>
      <%= if @show_edit_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Edit Playlist</h3>
            <.form
              for={@form}
              phx-submit="update_playlist"
              phx-change="validate"
              id="edit-playlist-form"
            >
              <div class="form-control mb-4">
                <.input field={@form[:name]} type="text" label="Name" required />
              </div>
              <div class="form-control mb-4">
                <.input field={@form[:description]} type="textarea" label="Description (optional)" />
              </div>
              <div class="modal-action">
                <button type="button" phx-click="close_edit_modal" class="btn btn-ghost">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary">
                  Save
                </button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="close_edit_modal"></div>
        </div>
      <% end %>

      <%!-- Delete Confirmation Modal --%>
      <%= if @show_delete_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Delete Playlist?</h3>
            <p class="py-4">
              Are you sure you want to delete "<span class="font-semibold">{@playlist.name}</span>"?
              This action cannot be undone.
            </p>
            <div class="modal-action">
              <button type="button" phx-click="close_delete_modal" class="btn btn-ghost">
                Cancel
              </button>
              <button type="button" phx-click="confirm_delete" class="btn btn-error">
                Delete
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="close_delete_modal"></div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
