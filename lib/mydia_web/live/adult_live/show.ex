defmodule MydiaWeb.AdultLive.Show do
  @moduledoc """
  LiveView for viewing individual adult media files and their metadata.
  """

  use MydiaWeb, :live_view

  alias Mydia.Library
  alias Mydia.Library.GeneratedMedia

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    file = Library.get_media_file!(id, preload: [:library_path])
    {prev_file, next_file} = Library.get_adjacent_media_files(id, library_path_type: :adult)

    {:ok,
     socket
     |> assign(:file, file)
     |> assign(:prev_file, prev_file)
     |> assign(:next_file, next_file)
     |> assign(:page_title, get_display_name(file))}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", %{"key" => "ArrowLeft"}, socket) do
    case socket.assigns.prev_file do
      nil -> {:noreply, socket}
      file -> {:noreply, push_navigate(socket, to: ~p"/adult/#{file.id}")}
    end
  end

  def handle_event("keydown", %{"key" => "ArrowRight"}, socket) do
    case socket.assigns.next_file do
      nil -> {:noreply, socket}
      file -> {:noreply, push_navigate(socket, to: ~p"/adult/#{file.id}")}
    end
  end

  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_file", _params, socket) do
    file = socket.assigns.file

    case Library.delete_media_file(file) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "File deleted successfully")
         |> push_navigate(to: ~p"/adult")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete file")}
    end
  end

  defp get_display_name(file) do
    case file.relative_path do
      nil -> "Unknown"
      path -> Path.basename(path)
    end
  end

  defp get_cover_url(file) do
    if file.cover_blob do
      GeneratedMedia.url_path(:cover, file.cover_blob)
    else
      "/images/no-poster.svg"
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

  defp format_date(nil), do: "-"

  defp format_date(%DateTime{} = date) do
    Calendar.strftime(date, "%Y-%m-%d %H:%M")
  end
end
