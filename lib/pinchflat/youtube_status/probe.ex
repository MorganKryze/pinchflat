defmodule Pinchflat.YoutubeStatus.Probe do
  @moduledoc """
  One question to YouTube, asked only while the queues are stopped.

  ## Why a probe is fine here and not otherwise

  A probe while the queues are running would add requests to a workload that is already
  asking as fast as it can. A probe while they are stopped replaces hundreds of requests
  with one every few minutes, and it is the only way for a pause to end on an answer
  instead of on the clock.

  ## What it asks

  The same pre-download check the download path runs, which needs no download and is the
  tier that failed first when this address was refused: indexing still worked and the
  check was already answering `No title found in player response`.

  ## What it asks about

  A video that has already downloaded, picked at random from the recent ones. A pending
  item would do, except that a pending item can be pending precisely because it is broken,
  and a probe pointed at a dead video would report a block that is not there and hold the
  queues shut for good.

  A failure that names a verdict on the video rather than a refusal of the address is
  treated as no answer at all, for the same reason.
  """

  import Ecto.Query, warn: false

  alias Pinchflat.Repo
  alias Pinchflat.YtDlp.Media
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Downloading.DownloadErrors

  # Enough that one dead video does not keep coming up, few enough that the query stays a
  # cheap indexed limit.
  @candidate_count 50

  @doc """
  Asks once.

  `:no_target` means there was nothing to ask about, which is not a block. Callers resume
  on it: staying stopped because the library is empty would be the worst kind of stuck.

  Returns :ok | :no_target | {:error, binary()}
  """
  def run do
    case target_url() do
      nil ->
        :no_target

      url ->
        case Media.get_downloadable_status(url) do
          {:ok, _status} -> :ok
          {:error, message} -> classify(message)
          {:error, message, _exit_code} -> classify(message)
        end
    end
  end

  # A verdict on the video says nothing about the address, and treating it as a refusal
  # would extend the pause forever over one deleted upload.
  defp classify(message) do
    if DownloadErrors.retryable?(message) do
      {:error, to_string(message)}
    else
      :no_target
    end
  end

  defp target_url do
    downloaded_urls() || any_url()
  end

  defp downloaded_urls do
    MediaItem
    |> where([mi], not is_nil(mi.media_downloaded_at))
    |> order_by([mi], desc: mi.media_downloaded_at)
    |> limit(@candidate_count)
    |> select([mi], mi.original_url)
    |> Repo.all()
    |> case do
      [] -> nil
      urls -> Enum.random(urls)
    end
  end

  defp any_url do
    MediaItem
    |> limit(1)
    |> select([mi], mi.original_url)
    |> Repo.one()
  end
end
