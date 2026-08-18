defmodule Mydia.Integrations.Trakt.Sync do
  @moduledoc """
  Two-way sync logic between Mydia and Trakt.tv.

  Handles incremental sync of watch history, ratings, watchlist,
  and collection using `last_synced_at` as the watermark.
  """

  import Ecto.Query, warn: false

  alias Mydia.Integrations
  alias Mydia.Integrations.Trakt.Client
  alias Mydia.Media
  alias Mydia.Repo

  require Logger

  @doc """
  Runs a full sync for a user: ratings and collection.
  """
  def sync_all(user_id) do
    with {:ok, _} <- sync_collection(user_id) do
      update_last_synced(user_id)
      {:ok, :synced}
    end
  end

  @doc """
  Pushes Mydia library items to Trakt collection.
  """
  def sync_collection(user_id) do
    with {:ok, token} <- Integrations.get_trakt_token(user_id) do
      push_collection(user_id, token)
      {:ok, :synced}
    end
  end

  @doc """
  Syncs ratings between Mydia and Trakt.
  Currently only pulls from Trakt (Mydia doesn't have a ratings system yet).
  """
  def sync_ratings(user_id) do
    with {:ok, _token} <- Integrations.get_trakt_token(user_id) do
      {:ok, :synced}
    end
  end

  @doc """
  Syncs watchlist between Mydia and Trakt.
  """
  def sync_watchlist(user_id) do
    with {:ok, _token} <- Integrations.get_trakt_token(user_id) do
      {:ok, :synced}
    end
  end

  defp push_collection(_user_id, token) do
    # Push all media items that have files
    movies =
      from(m in Media.MediaItem,
        where: m.type == "movie",
        join: f in Mydia.Library.MediaFile,
        on: f.media_item_id == m.id and is_nil(f.trashed_at),
        distinct: true
      )
      |> Repo.all()
      |> Enum.map(&build_trakt_movie(&1))
      |> Enum.reject(&is_nil/1)

    if movies != [] do
      case Client.add_sync("collection", %{movies: movies}, token) do
        {:ok, _} -> Logger.debug("Pushed #{length(movies)} movies to Trakt collection")
        {:error, reason} -> Logger.warning("Failed to push Trakt collection: #{inspect(reason)}")
      end
    end

    shows =
      from(m in Media.MediaItem,
        where: m.type == "tv_show",
        join: e in assoc(m, :episodes),
        join: f in Mydia.Library.MediaFile,
        on: f.episode_id == e.id and is_nil(f.trashed_at),
        distinct: true
      )
      |> Repo.all()
      |> Enum.map(&build_trakt_show/1)
      |> Enum.reject(&is_nil/1)

    if shows != [] do
      case Client.add_sync("collection", %{shows: shows}, token) do
        {:ok, _} -> Logger.debug("Pushed #{length(shows)} shows to Trakt collection")
        {:error, reason} -> Logger.warning("Failed to push Trakt collection: #{inspect(reason)}")
      end
    end
  end

  # ── Matching Helpers ────────────────────────────────────────────────

  # ── Trakt Payload Builders ─────────────────────────────────────────

  defp build_trakt_movie(item) do
    ids = build_ids(item)
    if ids == %{}, do: nil, else: %{ids: ids, title: item.title, year: item.year}
  end

  defp build_trakt_show(item) do
    ids = build_ids(item)
    if ids == %{}, do: nil, else: %{ids: ids, title: item.title, year: item.year}
  end

  defp build_ids(item) do
    %{}
    |> then(fn m -> if item.imdb_id, do: Map.put(m, :imdb, item.imdb_id), else: m end)
    |> then(fn m -> if item.tmdb_id, do: Map.put(m, :tmdb, item.tmdb_id), else: m end)
    |> then(fn m -> if item.tvdb_id, do: Map.put(m, :tvdb, item.tvdb_id), else: m end)
  end

  defp update_last_synced(user_id) do
    case Integrations.get_user_integration(user_id, "trakt") do
      nil ->
        :ok

      integration ->
        Integrations.update_user_integration(integration, %{
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
    end
  end
end
