defmodule Mydia.Downloads.Transcoding do
  @moduledoc false

  import Ecto.Query, warn: false
  import Mydia.QueryHelpers

  alias Mydia.Repo
  alias Mydia.Downloads.TranscodeJob
  alias Phoenix.PubSub
  require Logger

  ## Public Functions

  def get_or_create_job(media_file_id, resolution) do
    # Explicitly filter for download type jobs
    case Repo.get_by(TranscodeJob,
           media_file_id: media_file_id,
           resolution: resolution,
           type: "download"
         ) do
      nil ->
        attrs = %{
          media_file_id: media_file_id,
          resolution: resolution,
          type: "download",
          status: "pending",
          progress: 0.0
        }

        %TranscodeJob{}
        |> TranscodeJob.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, job} ->
            {:ok, job}

          {:error, %Ecto.Changeset{} = changeset} ->
            if unique_download_job_conflict?(changeset) do
              {:ok,
               Repo.get_by!(TranscodeJob,
                 media_file_id: media_file_id,
                 resolution: resolution,
                 type: "download"
               )}
            else
              {:error, changeset}
            end

          error ->
            error
        end

      job ->
        {:ok, job}
    end
  end

  defp unique_download_job_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {_field, {_message, opts}} ->
        opts[:constraint] == :unique and
          to_string(opts[:constraint_name]) == "transcode_jobs_media_file_id_resolution_index"

      _ ->
        false
    end)
  end

  def get_cached_transcode(media_file_id, resolution) do
    TranscodeJob
    |> where([j], j.media_file_id == ^media_file_id)
    |> where([j], j.resolution == ^resolution)
    |> where([j], j.type == "download")
    |> where([j], j.status == "ready")
    |> Repo.one()
  end

  def update_job_progress(%TranscodeJob{} = job, progress) do
    attrs = %{
      progress: progress,
      status: "transcoding"
    }

    attrs =
      if is_nil(job.started_at) do
        Map.put(attrs, :started_at, DateTime.utc_now())
      else
        attrs
      end

    case job
         |> TranscodeJob.changeset(attrs)
         |> Repo.update() do
      {:ok, updated_job} ->
        broadcast_job_update(updated_job.id)
        {:ok, updated_job}

      error ->
        error
    end
  end

  def complete_job(%TranscodeJob{} = job, output_path, file_size) do
    case job
         |> TranscodeJob.changeset(%{
           status: "ready",
           progress: 1.0,
           output_path: output_path,
           file_size: file_size,
           completed_at: DateTime.utc_now(),
           last_accessed_at: DateTime.utc_now()
         })
         |> Repo.update() do
      {:ok, updated_job} ->
        broadcast_job_update(updated_job.id)
        {:ok, updated_job}

      error ->
        error
    end
  end

  def fail_job(%TranscodeJob{} = job, error_message) do
    case job
         |> TranscodeJob.changeset(%{
           status: "failed",
           error: error_message
         })
         |> Repo.update() do
      {:ok, updated_job} ->
        broadcast_job_update(updated_job.id)
        {:ok, updated_job}

      error ->
        error
    end
  end

  def touch_last_accessed(%TranscodeJob{} = job) do
    job
    |> TranscodeJob.changeset(%{last_accessed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def broadcast_job_update(job_id) do
    PubSub.broadcast(Mydia.PubSub, "transcodes", {:job_updated, job_id})
  end

  def list_transcode_jobs_for_media_file(media_file_id) do
    TranscodeJob
    |> where([j], j.media_file_id == ^media_file_id)
    |> where([j], j.type == "download")
    |> order_by([j], desc: j.updated_at)
    |> Repo.all()
  end

  def list_transcode_jobs(opts \\ []) do
    TranscodeJob
    |> maybe_filter_status(opts[:status])
    |> maybe_preload(opts[:preload])
    |> order_by([j], desc: j.updated_at)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  def cancel_transcode_job(%TranscodeJob{} = job) do
    alias Mydia.Downloads.JobManager

    case job.type do
      "download" ->
        # Convert schema string resolution to atom for JobManager
        resolution_atom =
          case job.resolution do
            "original" -> :original
            "1080p" -> :p1080
            "720p" -> :p720
            "480p" -> :p480
            _ -> :p720
          end

        # Cancel in JobManager
        JobManager.cancel_job(job.media_file_id, resolution_atom)

      _ ->
        :ok
    end

    # Delete from DB
    Repo.delete(job)

    # Clean up output file if it exists (only for downloads)
    if job.output_path && File.exists?(job.output_path) do
      File.rm(job.output_path)
    end

    broadcast_job_update(job.id)
    {:ok, job}
  end

  def delete_all_completed_jobs do
    jobs =
      TranscodeJob
      |> where([j], j.status in ["ready", "failed"])
      |> Repo.all()

    Enum.each(jobs, &cancel_transcode_job/1)
  end

  ## Private Functions

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, statuses) when is_list(statuses),
    do: where(query, [j], j.status in ^statuses)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)
end
