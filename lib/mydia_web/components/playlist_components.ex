defmodule MydiaWeb.PlaylistComponents do
  @moduledoc """
  Reusable components for playlist views.
  """
  use Phoenix.Component

  import MydiaWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: MydiaWeb.Endpoint,
    router: MydiaWeb.Router,
    statics: MydiaWeb.static_paths()

  @doc """
  Renders a playlist card for the playlist index.

  ## Attributes

    * `:playlist` - Required. The playlist struct to display.
  """
  attr :playlist, :map, required: true

  def playlist_card(assigns) do
    ~H"""
    <.link navigate={~p"/music/playlists/#{@playlist.id}"} class="group">
      <div class="card bg-base-100 shadow-lg hover:shadow-xl transition-shadow overflow-hidden">
        <figure class="relative aspect-square bg-base-200">
          <%= if @playlist.cover_url do %>
            <img
              src={@playlist.cover_url}
              alt={@playlist.name}
              class="w-full h-full object-cover"
            />
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <.icon name="hero-musical-note" class="w-16 h-16 text-base-content/20" />
            </div>
          <% end %>
          <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
            <.icon name="hero-play-circle" class="w-16 h-16 text-white" />
          </div>
        </figure>
        <div class="card-body p-3">
          <h3 class="font-bold truncate">{@playlist.name}</h3>
          <p class="text-sm text-base-content/60">
            {@playlist.track_count || 0} tracks • {format_duration(@playlist.total_duration)}
          </p>
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Renders the header section for a playlist detail view.

  ## Attributes

    * `:playlist` - Required. The playlist struct.
    * `:on_edit` - Event name for editing the playlist.
    * `:on_delete` - Event name for deleting the playlist.
  """
  attr :playlist, :map, required: true
  attr :on_edit, :string, default: "edit_playlist"
  attr :on_delete, :string, default: "delete_playlist"

  def playlist_header(assigns) do
    ~H"""
    <div class="flex flex-col md:flex-row gap-6 mb-8">
      <%!-- Playlist cover --%>
      <div class="flex-shrink-0">
        <div class="w-48 h-48 md:w-64 md:h-64 bg-base-200 rounded-lg shadow-lg flex items-center justify-center overflow-hidden">
          <%= if @playlist.cover_url do %>
            <img
              src={@playlist.cover_url}
              alt={@playlist.name}
              class="w-full h-full object-cover"
            />
          <% else %>
            <.icon name="hero-musical-note" class="w-24 h-24 text-base-content/20" />
          <% end %>
        </div>
      </div>

      <%!-- Playlist info --%>
      <div class="flex-1 flex flex-col justify-end">
        <p class="text-sm text-base-content/60 uppercase font-medium mb-2">Playlist</p>
        <h1 class="text-3xl md:text-4xl font-bold mb-4">{@playlist.name}</h1>

        <%= if @playlist.description do %>
          <p class="text-base-content/70 mb-4">{@playlist.description}</p>
        <% end %>

        <p class="text-sm text-base-content/60 mb-6">
          {@playlist.track_count || 0} tracks • {format_duration(@playlist.total_duration)}
        </p>

        <div class="flex gap-3">
          <div class="dropdown dropdown-end ml-auto">
            <div tabindex="0" role="button" class="btn btn-ghost btn-circle">
              <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow-lg"
            >
              <li>
                <button type="button" phx-click={@on_edit}>
                  <.icon name="hero-pencil" class="w-4 h-4" /> Edit
                </button>
              </li>
              <li>
                <button type="button" phx-click={@on_delete} class="text-error">
                  <.icon name="hero-trash" class="w-4 h-4" /> Delete
                </button>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a track row in the playlist.

  ## Attributes

    * `:playlist_track` - Required. The playlist track with preloaded track.
    * `:index` - The display position (1-based).
    * `:on_remove` - Event for removing this track.
  """
  attr :playlist_track, :map, required: true
  attr :index, :integer, required: true
  attr :on_remove, :string, default: "remove_track"

  def playlist_track_row(assigns) do
    ~H"""
    <tr
      id={"playlist-track-#{@playlist_track.id}"}
      class="group hover:bg-base-200"
    >
      <td class="w-12 text-base-content/50">{@index}</td>
      <td>
        <div class="flex items-center gap-3">
          <%= if @playlist_track.track.album && @playlist_track.track.album.cover_url do %>
            <img
              src={@playlist_track.track.album.cover_url}
              alt={@playlist_track.track.album.title}
              class="w-10 h-10 rounded object-cover"
            />
          <% else %>
            <div class="w-10 h-10 rounded bg-base-200 flex items-center justify-center">
              <.icon name="hero-musical-note" class="w-5 h-5 text-base-content/30" />
            </div>
          <% end %>
          <div>
            <div class="font-medium">{@playlist_track.track.title}</div>
            <div class="text-sm text-base-content/60">
              <%= if @playlist_track.track.artist do %>
                {@playlist_track.track.artist.name}
              <% end %>
            </div>
          </div>
        </div>
      </td>
      <td class="hidden sm:table-cell text-base-content/60">
        <%= if @playlist_track.track.album do %>
          {@playlist_track.track.album.title}
        <% end %>
      </td>
      <td class="text-right text-base-content/60">
        {format_track_duration(@playlist_track.track.duration)}
      </td>
      <td class="w-12">
        <button
          type="button"
          phx-click={@on_remove}
          phx-value-playlist-track-id={@playlist_track.id}
          class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100"
          onclick="event.stopPropagation();"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </td>
    </tr>
    """
  end

  @doc """
  Renders an "Add to Playlist" dropdown menu.

  ## Attributes

    * `:playlists` - Required. List of user playlists.
    * `:on_add` - Event name for adding to playlist.
    * `:on_create` - Event name for creating a new playlist.
    * `:track_id` - ID of track to add (for single track).
    * `:album_id` - ID of album to add (for album tracks).
    * `:class` - Additional CSS classes.
  """
  attr :playlists, :list, required: true
  attr :on_add, :string, default: "add_to_playlist"
  attr :on_create, :string, default: "create_playlist_for_track"
  attr :track_id, :string, default: nil
  attr :album_id, :string, default: nil
  attr :class, :string, default: nil

  def add_to_playlist_dropdown(assigns) do
    ~H"""
    <div class={["dropdown dropdown-end", @class]}>
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-1">
        <.icon name="hero-plus" class="w-4 h-4" />
        <span class="hidden sm:inline">Add to Playlist</span>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box z-[1] w-56 p-2 shadow-lg max-h-80 overflow-y-auto"
      >
        <li class="menu-title">
          <span>Add to playlist</span>
        </li>
        <li>
          <button
            type="button"
            phx-click={@on_create}
            phx-value-track-id={@track_id}
            phx-value-album-id={@album_id}
            class="text-primary"
          >
            <.icon name="hero-plus-circle" class="w-4 h-4" /> Create new playlist
          </button>
        </li>
        <%= if @playlists != [] do %>
          <li class="menu-title mt-2">
            <span>Your playlists</span>
          </li>
          <%= for playlist <- @playlists do %>
            <li>
              <button
                type="button"
                phx-click={@on_add}
                phx-value-playlist-id={playlist.id}
                phx-value-track-id={@track_id}
                phx-value-album-id={@album_id}
              >
                <.icon name="hero-musical-note" class="w-4 h-4" />
                {playlist.name}
              </button>
            </li>
          <% end %>
        <% end %>
      </ul>
    </div>
    """
  end

  # Private helper functions

  defp format_duration(nil), do: "0 min"
  defp format_duration(0), do: "0 min"

  defp format_duration(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      hours > 0 -> "#{hours} hr #{minutes} min"
      minutes > 0 -> "#{minutes} min"
      true -> "< 1 min"
    end
  end

  defp format_track_duration(nil), do: "-"

  defp format_track_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(to_string(remaining_seconds), 2, "0")}"
  end
end
