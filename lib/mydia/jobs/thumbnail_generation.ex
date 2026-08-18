defmodule Mydia.Jobs.ThumbnailGeneration do
  @moduledoc """
  Background job for generating thumbnails and cover images from video files.

  This job processes media files to generate:
  - Cover thumbnails (static image from video)
  - Optionally sprite sheets and VTT files for scrubbing
  - Optionally video previews for hover playback

  ## Features

  - Batch processing to avoid overwhelming the system
  - Progress tracking via PubSub for UI updates
  - Exponential backoff retry on failures
  - Support for single file, batch, and library-wide generation

  ## Usage

      # Generate for a single file
      Mydia.Jobs.ThumbnailGeneration.enqueue_file(media_file_id)

      # Generate for all files in a library path
      Mydia.Jobs.ThumbnailGeneration.enqueue_library(library_path_id)

      # Generate for all files missing thumbnails
      Mydia.Jobs.ThumbnailGeneration.enqueue_missing()

      # Include sprites and video previews
      Mydia.Jobs.ThumbnailGeneration.enqueue_file(id)

  ## Job Arguments

  - `media_file_id` - Generate thumbnail for a single file
  - `media_file_ids` - Generate thumbnails for a batch of files
  - `library_path_id` - Generate thumbnails for all files in a library
  - `mode` - Processing mode: "single", "batch", or "missing"
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 5,
    priority: 2

  require Logger

  import Ecto.Query

  alias Mydia.Library
  alias Mydia.Library.MediaFile
  alias Mydia.Library.ThumbnailGenerator
  alias Mydia.Repo

  @pubsub Mydia.PubSub
  @topic "thumbnail_generation"

  # Default batch size for processing multiple files
  @default_batch_size 10

  # Backoff schedule in seconds
  @backoff_schedule [30, 120, 300, 900, 1800]

  ## Public API

  @doc """
  Returns the PubSub topic for thumbnail generation progress.
  """
  def topic, do: @topic

  @doc """
  Subscribes the current process to thumbnail generation progress updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Enqueues a job to generate a thumbnail for a single media file.
  """
  def enqueue_file(media_file_id) when is_binary(media_file_id) do
    %{
      mode: "single",
      media_file_id: media_file_id
    }
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a job to generate thumbnails for multiple media files.

  Files are processed in batches to avoid overwhelming the system.
  """
  def enqueue_batch(media_file_ids) when is_list(media_file_ids) do
    %{
      mode: "batch",
      media_file_ids: media_file_ids
    }
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a job to generate thumbnails for all files in a library path.

  ## Options
    - `:regenerate` - Regenerate even if thumbnails exist (default: false)
  """
  def enqueue_library(library_path_id, opts \\ []) when is_binary(library_path_id) do
    %{
      mode: "library",
      library_path_id: library_path_id,
      regenerate: Keyword.get(opts, :regenerate, false)
    }
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a job to generate thumbnails for all files missing them.

  ## Options
    - `:library_type` - Only process files from this library type (optional)
  """
  def enqueue_missing(opts \\ []) do
    args = %{mode: "missing"}

    args =
      case Keyword.get(opts, :library_type) do
        nil -> args
        type -> Map.put(args, :library_type, to_string(type))
      end

    args
    |> new()
    |> Oban.insert()
  end

  @doc """
  Cancels all pending thumbnail generation jobs.

  Returns the number of jobs cancelled.
  """
  def cancel_all do
    {count, _} =
      Oban.Job
      |> where([j], j.worker == ^inspect(__MODULE__))
      |> where([j], j.state in ["available", "scheduled", "retryable"])
      |> Repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])

    broadcast_progress(%{event: :cancelled, count: count})
    {:ok, count}
  end

  defmodule Args do
    @moduledoc false
    defstruct [
      :mode,
      :media_file_id,
      :media_file_ids,
      :library_path_id,
      :library_type,
      regenerate: false
    ]

    @type t :: %__MODULE__{
            mode: String.t() | nil,
            media_file_id: String.t() | nil,
            media_file_ids: [String.t()] | nil,
            library_path_id: String.t() | nil,
            library_type: String.t() | nil,
            regenerate: boolean()
          }

    def parse(%{"mode" => "single", "media_file_id" => id}) do
      %__MODULE__{mode: "single", media_file_id: id}
    end

    def parse(%{"mode" => "batch", "media_file_ids" => ids}) do
      %__MODULE__{mode: "batch", media_file_ids: ids}
    end

    def parse(%{"mode" => "library", "library_path_id" => id} = raw) do
      %__MODULE__{
        mode: "library",
        library_path_id: id,
        regenerate: Map.get(raw, "regenerate", false)
      }
    end

    def parse(%{"mode" => "missing"} = raw) do
      %__MODULE__{mode: "missing", library_type: Map.get(raw, "library_type")}
    end
  end

  ## Oban Worker Implementation

  @spec perform(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()} | {:snooze, pos_integer()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mode" => "single"} = raw_args}) do
    args = Args.parse(raw_args)

    case process_single_file(args.media_file_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"mode" => "batch"} = raw_args}) do
    args = Args.parse(raw_args)
    process_batch(args.media_file_ids)
  end

  def perform(%Oban.Job{args: %{"mode" => "library"} = raw_args}) do
    args = Args.parse(raw_args)

    process_library(args.library_path_id, args.regenerate)
    :ok
  end

  def perform(%Oban.Job{args: %{"mode" => "missing"} = raw_args}) do
    args = Args.parse(raw_args)

    process_missing(args.library_type)
    :ok
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    index = min(attempt - 1, length(@backoff_schedule) - 1)
    Enum.at(@backoff_schedule, index)
  end

  ## Private Implementation

  defp process_single_file(media_file_id) do
    broadcast_progress(%{event: :started, total: 1, completed: 0})

    media_file =
      MediaFile
      |> Repo.get(media_file_id)
      |> Repo.preload(:library_path)

    result = generate_for_file(media_file)

    case result do
      {:ok, _} ->
        broadcast_progress(%{event: :completed, total: 1, completed: 1, failed: 0})
        {:ok, :completed}

      {:error, reason} ->
        broadcast_progress(%{event: :completed, total: 1, completed: 0, failed: 1})
        {:error, reason}
    end
  end

  defp process_batch(media_file_ids) do
    total = length(media_file_ids)
    broadcast_progress(%{event: :started, total: total, completed: 0})

    {completed, failed} =
      media_file_ids
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {id, index}, {completed, failed} ->
        media_file =
          MediaFile
          |> Repo.get(id)
          |> Repo.preload(:library_path)

        case generate_for_file(media_file) do
          {:ok, _} ->
            broadcast_progress(%{
              event: :progress,
              total: total,
              completed: completed + 1,
              current: index
            })

            {completed + 1, failed}

          {:error, reason} ->
            Logger.warning("Failed to generate thumbnail for #{id}: #{inspect(reason)}")
            {completed, failed + 1}
        end
      end)

    broadcast_progress(%{event: :completed, total: total, completed: completed, failed: failed})
    :ok
  end

  defp process_library(library_path_id, regenerate) do
    # Get all video files in the library
    query =
      from mf in MediaFile,
        where: mf.library_path_id == ^library_path_id,
        select: mf.id

    query =
      if regenerate do
        query
      else
        from mf in query, where: is_nil(mf.cover_blob)
      end

    file_ids = Repo.all(query)

    if file_ids == [] do
      broadcast_progress(%{event: :completed, total: 0, completed: 0, failed: 0})
      {:ok, :no_files}
    else
      # Process in batches
      process_in_batches(file_ids)
      {:ok, :completed}
    end
  end

  defp process_missing(library_type) do
    # Query files missing thumbnails
    query =
      from mf in MediaFile,
        join: lp in assoc(mf, :library_path),
        where: is_nil(mf.cover_blob),
        select: mf.id

    query =
      if library_type do
        type_atom = String.to_existing_atom(library_type)
        from [mf, lp] in query, where: lp.type == ^type_atom
      else
        query
      end

    file_ids = Repo.all(query)

    if file_ids == [] do
      broadcast_progress(%{event: :completed, total: 0, completed: 0, failed: 0})
      {:ok, :no_files}
    else
      process_in_batches(file_ids)
      {:ok, :completed}
    end
  end

  defp process_in_batches(file_ids) do
    total = length(file_ids)
    broadcast_progress(%{event: :started, total: total, completed: 0})

    {completed, failed} =
      file_ids
      |> Enum.chunk_every(@default_batch_size)
      |> Enum.with_index()
      |> Enum.reduce({0, 0}, fn {batch, batch_index}, {completed_acc, failed_acc} ->
        batch_start = batch_index * @default_batch_size

        {batch_completed, batch_failed} =
          batch
          |> Enum.with_index(batch_start + 1)
          |> Enum.reduce({0, 0}, fn {id, index}, {c, f} ->
            media_file =
              MediaFile
              |> Repo.get(id)
              |> Repo.preload(:library_path)

            case generate_for_file(media_file) do
              {:ok, _} ->
                broadcast_progress(%{
                  event: :progress,
                  total: total,
                  completed: completed_acc + c + 1,
                  current: index
                })

                {c + 1, f}

              {:error, reason} ->
                Logger.warning("Failed to generate thumbnail for #{id}: #{inspect(reason)}")
                {c, f + 1}
            end
          end)

        {completed_acc + batch_completed, failed_acc + batch_failed}
      end)

    broadcast_progress(%{event: :completed, total: total, completed: completed, failed: failed})
    {completed, failed}
  end

  defp generate_for_file(nil) do
    {:error, :file_not_found}
  end

  defp generate_for_file(%MediaFile{} = media_file) do
    # Check if FFmpeg is available
    if ThumbnailGenerator.ffmpeg_available?() do
      # Generate cover thumbnail
      with {:ok, cover_checksum} <- ThumbnailGenerator.generate_cover(media_file) do
        attrs = %{cover_blob: cover_checksum, generated_at: DateTime.utc_now()}

        Library.update_media_file(media_file, attrs)
      end
    else
      {:error, :ffmpeg_not_found}
    end
  end

  defp broadcast_progress(data) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:thumbnail_generation, data})
  end
end
