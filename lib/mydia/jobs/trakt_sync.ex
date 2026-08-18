defmodule Mydia.Jobs.TraktSync do
  @moduledoc """
  Oban worker for syncing data between Mydia and Trakt.tv.

  Supports sync types: "ratings", "collection", "watchlist", "full".
  """
  use Oban.Worker, queue: :integrations, max_attempts: 3

  alias Mydia.Integrations.Trakt.Sync

  require Logger

  defmodule Args do
    @moduledoc false
    defstruct [:user_id, :sync_type]

    @type t :: %__MODULE__{
            user_id: String.t() | nil,
            sync_type: String.t() | nil
          }

    def parse(%{"user_id" => user_id, "sync_type" => sync_type}) do
      %__MODULE__{user_id: user_id, sync_type: sync_type}
    end
  end

  @spec perform(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()} | {:snooze, pos_integer()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: raw_args}) do
    args = Args.parse(raw_args)
    user_id = args.user_id
    sync_type = args.sync_type
    Logger.info("Starting Trakt #{sync_type} sync for user #{user_id}")

    result =
      case sync_type do
        "full" -> Sync.sync_all(user_id)
        "ratings" -> Sync.sync_ratings(user_id)
        "collection" -> Sync.sync_collection(user_id)
        "watchlist" -> Sync.sync_watchlist(user_id)
        other -> {:error, "Unknown sync type: #{other}"}
      end

    case result do
      {:ok, _} ->
        Logger.info("Trakt #{sync_type} sync completed for user #{user_id}")
        :ok

      {:error, :not_connected} ->
        Logger.debug("Skipping Trakt sync for user #{user_id}: not connected")
        :ok

      {:error, :disabled} ->
        Logger.debug("Skipping Trakt sync for user #{user_id}: disabled")
        :ok

      {:error, reason} ->
        Logger.error("Trakt #{sync_type} sync failed for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
