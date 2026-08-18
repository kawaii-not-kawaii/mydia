defmodule MydiaWeb.AdultLive.Index do
  @moduledoc """
  LiveView for browsing adult library content.

  Displays media files from adult library paths with thumbnail support,
  search, filtering, and sorting capabilities.
  """

  use MydiaWeb, :live_view

  alias Mydia.Library
  alias Mydia.Library.GeneratedMedia
  alias Mydia.Jobs.ThumbnailGeneration

  @items_per_page 50
  @items_per_scroll 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mydia.PubSub, "library_scanner")
      ThumbnailGeneration.subscribe()
    end

    {:ok,
     socket
     |> assign(:view_mode, :grid)
     |> assign(:search_query, "")
     |> assign(:sort_by, "added_desc")
     |> assign(:page, 0)
     |> assign(:has_more, true)
     |> assign(:page_title, "Adult")
     |> assign(:scanning, false)
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:all_visible_ids, MapSet.new())
     |> assign(:show_delete_modal, false)
     |> assign(:delete_files, false)
     |> stream(:files, [])}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, load_files(socket, reset: true)}
  end

  @impl true
  def handle_event("toggle_view", %{"mode" => mode}, socket) do
    view_mode = String.to_existing_atom(mode)

    {:noreply,
     socket
     |> assign(:view_mode, view_mode)
     |> assign(:page, 0)
     |> load_files(reset: true)}
  end

  def handle_event("search", params, socket) do
    query = params["search"] || params["value"] || ""

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:page, 0)
     |> load_files(reset: true)}
  end

  def handle_event("filter", params, socket) do
    sort_by = params["sort_by"] || socket.assigns.sort_by

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:page, 0)
     |> load_files(reset: true)}
  end

  def handle_event("load_more", _params, socket) do
    if socket.assigns.has_more do
      {:noreply,
       socket
       |> update(:page, &(&1 + 1))
       |> load_files(reset: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("trigger_rescan", _params, socket) do
    case Library.trigger_adult_library_scan() do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:scanning, true)
         |> put_flash(:info, "Library scan started...")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start library scan")}
    end
  end

  def handle_event("toggle_selection_mode", _params, socket) do
    selection_mode = !socket.assigns.selection_mode

    socket =
      if selection_mode do
        socket
      else
        # Exiting selection mode - clear selection
        assign(socket, :selected_ids, MapSet.new())
      end

    {:noreply, assign(socket, :selection_mode, selection_mode)}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected_ids = socket.assigns.selected_ids

    updated_ids =
      if MapSet.member?(selected_ids, id) do
        MapSet.delete(selected_ids, id)
      else
        MapSet.put(selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, updated_ids)}
  end

  def handle_event("select_all", _params, socket) do
    # Get all visible files from the current stream
    all_files =
      Library.list_media_files(library_path_type: :adult)

    # Apply search filter if present
    files =
      if socket.assigns.search_query != "" do
        query = String.downcase(socket.assigns.search_query)

        Enum.filter(all_files, fn file ->
          filename = file.relative_path || ""
          String.contains?(String.downcase(filename), query)
        end)
      else
        all_files
      end

    all_ids = MapSet.new(files, & &1.id)

    {:noreply, assign(socket, :selected_ids, all_ids)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  def handle_event("toggle_select_all", _params, socket) do
    # Toggle between selecting all visible items and clearing selection
    all_visible_ids = socket.assigns.all_visible_ids
    selected_ids = socket.assigns.selected_ids

    new_selected_ids =
      if MapSet.equal?(selected_ids, all_visible_ids) and MapSet.size(all_visible_ids) > 0 do
        # All are selected, so clear
        MapSet.new()
      else
        # Not all selected, so select all
        all_visible_ids
      end

    {:noreply, assign(socket, :selected_ids, new_selected_ids)}
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())}
  end

  def handle_event("keydown", %{"key" => "a", "ctrlKey" => true}, socket) do
    # Ctrl+A - select all
    all_files =
      Library.list_media_files(library_path_type: :adult)

    files =
      if socket.assigns.search_query != "" do
        query = String.downcase(socket.assigns.search_query)

        Enum.filter(all_files, fn file ->
          filename = file.relative_path || ""
          String.contains?(String.downcase(filename), query)
        end)
      else
        all_files
      end

    all_ids = MapSet.new(files, & &1.id)

    {:noreply, assign(socket, :selected_ids, all_ids)}
  end

  def handle_event("keydown", _params, socket) do
    # Ignore other key events
    {:noreply, socket}
  end

  def handle_event("show_delete_confirmation", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, true)
     |> assign(:delete_files, false)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:delete_files, false)}
  end

  def handle_event("toggle_delete_files", %{"delete_files" => value}, socket) do
    delete_files = value == "true"
    {:noreply, assign(socket, :delete_files, delete_files)}
  end

  def handle_event("batch_delete_confirmed", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_ids)
    delete_files = socket.assigns.delete_files

    # Get the media files to delete
    media_files = Enum.map(selected_ids, &Library.get_media_file!/1)

    # Delete files from disk if requested
    if delete_files do
      Library.delete_media_files_from_disk(media_files)
    end

    # Delete records from database
    deleted_count =
      media_files
      |> Enum.map(&Library.delete_media_file/1)
      |> Enum.count(&match?({:ok, _}, &1))

    message =
      if delete_files do
        "#{deleted_count} #{pluralize_files(deleted_count)} deleted (including files)"
      else
        "#{deleted_count} #{pluralize_files(deleted_count)} removed from library"
      end

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:show_delete_modal, false)
     |> assign(:delete_files, false)
     |> load_files(reset: true)}
  end

  @impl true
  def handle_info({:library_scan_started, %{type: :adult}}, socket) do
    {:noreply, assign(socket, :scanning, true)}
  end

  def handle_info({:library_scan_started, _}, socket) do
    # Ignore scans for other library types
    {:noreply, socket}
  end

  def handle_info(
        {:library_scan_completed,
         %{
           type: :adult,
           new_files: new_files,
           modified_files: modified_files,
           deleted_files: deleted_files
         }},
        socket
      ) do
    total_changes = new_files + modified_files + deleted_files

    message =
      if total_changes > 0 do
        parts = []
        parts = if new_files > 0, do: ["#{new_files} new" | parts], else: parts
        parts = if modified_files > 0, do: ["#{modified_files} modified" | parts], else: parts
        parts = if deleted_files > 0, do: ["#{deleted_files} removed" | parts], else: parts
        "Library scan completed: " <> Enum.join(parts, ", ")
      else
        "Library scan completed: No changes detected"
      end

    {:noreply,
     socket
     |> assign(:scanning, false)
     |> put_flash(:info, message)
     |> load_files(reset: true)}
  end

  def handle_info({:library_scan_completed, _}, socket) do
    # Ignore completions for other library types
    {:noreply, socket}
  end

  def handle_info({:library_scan_failed, %{error: error}}, socket) do
    {:noreply,
     socket
     |> assign(:scanning, false)
     |> put_flash(:error, "Library scan failed: #{error}")}
  end

  # Thumbnail generation updates - reload files when thumbnails are generated
  def handle_info({:thumbnail_generation, %{event: :completed}}, socket) do
    {:noreply, load_files(socket, reset: true)}
  end

  def handle_info({:thumbnail_generation, _}, socket) do
    # Ignore progress and started events to avoid excessive reloads
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    # Ignore other PubSub messages
    {:noreply, socket}
  end

  defp load_files(socket, opts) do
    reset? = Keyword.get(opts, :reset, false)
    page = if reset?, do: 0, else: socket.assigns.page
    offset = if page == 0, do: 0, else: @items_per_page + (page - 1) * @items_per_scroll
    limit = if page == 0, do: @items_per_page, else: @items_per_scroll

    # Get all media files from adult library paths
    all_files =
      Library.list_media_files(
        library_path_type: :adult,
        preload: [:library_path]
      )

    # Apply search filter
    files =
      if socket.assigns.search_query != "" do
        query = String.downcase(socket.assigns.search_query)

        Enum.filter(all_files, fn file ->
          filename = file.relative_path || ""
          String.contains?(String.downcase(filename), query)
        end)
      else
        all_files
      end

    # Apply sorting
    files = apply_sorting(files, socket.assigns.sort_by)

    # Apply pagination
    paginated_files = files |> Enum.drop(offset) |> Enum.take(limit)
    has_more = length(files) > offset + limit

    # Track all visible file IDs for "Select All" functionality
    all_visible_ids = MapSet.new(files, & &1.id)

    socket =
      socket
      |> assign(:has_more, has_more)
      |> assign(:files_empty?, reset? and files == [])
      |> assign(:all_visible_ids, all_visible_ids)

    if reset? do
      stream(socket, :files, paginated_files, reset: true)
    else
      stream(socket, :files, paginated_files)
    end
  end

  defp apply_sorting(files, sort_by) do
    case sort_by do
      "name_asc" ->
        Enum.sort_by(files, &get_filename(&1), :asc)

      "name_desc" ->
        Enum.sort_by(files, &get_filename(&1), :desc)

      "size_asc" ->
        Enum.sort_by(files, & &1.size, :asc)

      "size_desc" ->
        Enum.sort_by(files, & &1.size, :desc)

      "added_asc" ->
        Enum.sort_by(files, & &1.inserted_at, :asc)

      "added_desc" ->
        Enum.sort_by(files, & &1.inserted_at, :desc)

      _ ->
        Enum.sort_by(files, & &1.inserted_at, :desc)
    end
  end

  defp get_filename(file) do
    case file.relative_path do
      nil -> ""
      path -> Path.basename(path) |> String.downcase()
    end
  end

  defp get_display_name(file) do
    case file.relative_path do
      nil -> "Unknown"
      path -> Path.basename(path)
    end
  end

  defp get_thumbnail_url(file) do
    if file.cover_blob do
      GeneratedMedia.url_path(:cover, file.cover_blob)
    else
      "/images/no-poster.svg"
    end
  end

  defp get_duration(file) do
    case file.metadata do
      %{"duration" => duration} when is_number(duration) -> trunc(duration)
      _ -> nil
    end
  end

  defp format_file_size(nil), do: "-"

  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 0)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_resolution(nil), do: nil
  defp format_resolution(""), do: nil
  defp format_resolution(resolution), do: resolution

  defp format_date(nil), do: "-"

  defp format_date(%DateTime{} = date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end

  defp item_selected?(selected_ids, item_id) do
    MapSet.member?(selected_ids, item_id)
  end

  defp pluralize_files(1), do: "file"
  defp pluralize_files(_), do: "files"
end
