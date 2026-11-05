require "net/http"
require "json"
require "timeout"

class DiscordInteractionRelay
  class Unavailable < StandardError; end

  def self.call(body:, signature:, timestamp:, http: Net::HTTP)
    uri = URI(ENV.fetch("DISCORD_STAGING_INTERACTIONS_URL"))
    unless uri.scheme == "https" && uri.host.present? && uri.userinfo.nil? && uri.path == "/discord/interactions" && uri.query.nil? && uri.fragment.nil?
      raise Unavailable, "Invalid staging interactions URL"
    end
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Signature-Ed25519"] = signature
    request["X-Signature-Timestamp"] = timestamp
    request.body = body

    # Discord needs an initial reply within three seconds, including relay time.
    response = Timeout.timeout(2, Unavailable) do
      http.start(uri.host, uri.port, use_ssl: true, open_timeout: 0.5, ssl_timeout: 0.5,
        read_timeout: 1, write_timeout: 0.5, max_retries: 0) { |client| client.request(request) }
    end
    raise Unavailable, "Staging returned HTTP #{response.code}" unless response.code.to_i == 200
    raise Unavailable, "Staging reply too large" if response.body.bytesize > 65_536
    data = JSON.parse(response.body)
    unless data.is_a?(Hash) && data["type"] == 4 && data["data"].is_a?(Hash) && (data["data"]["flags"].to_i & 64) == 64
      raise Unavailable, "Staging did not return a private reply"
    end
    data
  rescue Unavailable
    raise
  rescue StandardError => error
    raise Unavailable, "Staging relay failed (#{error.class})"
  end
end
