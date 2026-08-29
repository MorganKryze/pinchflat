defmodule PinchflatWeb.Settings.SettingHTML do
  use PinchflatWeb, :html

  embed_templates "setting_html/*"

  @doc """
  Renders a setting form.
  """
  attr :conn, Plug.Conn, required: true
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true

  def setting_form(assigns)

  def apprise_server_help do
    url = "https://github.com/caronc/apprise/wiki/URLBasics"

    ~s(Server endpoint for Apprise notifications when new media is found. See <a href="#{url}" class="#{help_link_classes()}" target="_blank">Apprise docs</a> for more information)
  end

  def youtube_api_help do
    url = "https://github.com/kieraneglin/pinchflat/wiki/Generating-a-YouTube-API-key"

    ~s(API key for YouTube Data API v3. Greatly improves the accuracy of Fast Indexing. See <a href="#{url}" class="#{help_link_classes()}" target="_blank">here</a> for details on generating an API key)
  end

  def diagnostic_info_string do
    """
    - App Version: #{Application.spec(:pinchflat)[:vsn]}
    - yt-dlp Version: #{Settings.get!(:yt_dlp_version)}
    - yt-dlp Last Update: #{yt_dlp_update_summary()}
    - Apprise Version: #{Settings.get!(:apprise_version)}
    - System Architecture: #{to_string(:erlang.system_info(:system_architecture))}
    - Timezone: #{Application.get_env(:pinchflat, :timezone)}
    """
  end

  # The version alone does not say whether it is the version yt-dlp should be on: a
  # self-update that has been failing for months looks identical to one that has nothing
  # to do.
  defp yt_dlp_update_summary do
    case {Settings.get!(:yt_dlp_last_update_attempted_at), Settings.get!(:yt_dlp_last_update_error)} do
      {nil, _} -> "never attempted"
      {attempted_at, nil} -> "ok (#{attempted_at})"
      {attempted_at, error} -> "FAILED (#{attempted_at}): #{error}"
    end
  end

  defp help_link_classes do
    "underline decoration-bodydark decoration-1 hover:decoration-white"
  end
end
