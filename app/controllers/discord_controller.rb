class DiscordController < ActionController::Base
  skip_forgery_protection
  before_action :verify_signature

  def create
    payload = JSON.parse(request.raw_post)
    return render json: { type: 1 } if payload["type"] == 1
    unless payload["type"] == 2 && payload.dig("data", "name") == ENV.fetch("DISCORD_COMMAND", "bingo") &&
        payload.dig("member", "user", "id").present?
      return head :forbidden
    end
    return head :bad_request if payload["id"].blank?
    unless payload["guild_id"] == ENV.fetch("DISCORD_GUILD_ID", "")
      staging_guild = ENV["DISCORD_STAGING_GUILD_ID"].presence
      return head :forbidden unless staging_guild && payload["guild_id"] == staging_guild
      return render json: DiscordInteractionRelay.call(body: request.raw_post,
        signature: request.headers["X-Signature-Ed25519"], timestamp: request.headers["X-Signature-Timestamp"])
    end
    if LoginToken.exists?(interaction_id: payload["id"])
      return private_reply("Ten link został już wysłany. Użyj /#{ENV.fetch('DISCORD_COMMAND', 'bingo')} ponownie, aby otrzymać nowy.")
    end
    base_url = ENV["APP_URL"].presence
    unless base_url
      Rails.logger.error("Discord login unavailable: APP_URL is missing from the application configuration.")
      return private_reply("Logowanie jest chwilowo niedostępne. Administrator musi sprawdzić konfigurację aplikacji.")
    end
    user = payload.fetch("member").fetch("user")
    participant = Participant.create_or_find_by!(discord_id: user.fetch("id")) do |record|
      record.display_name = display_name(payload, user)
    end
    participant.update!(display_name: display_name(payload, user))
    raw = LoginToken.issue!(participant: participant, interaction_id: payload.fetch("id"))
    url = "#{base_url}/login?token=#{raw}"
    private_reply("Link do logowania jest ważny przez 10 minut. Głosy są przypisane do konta Discord.",
      components: [ { type: 1, components: [ { type: 2, style: 5, label: "Otwórz TGA Bingo", url: url } ] } ])
  rescue JSON::ParserError, KeyError
    head :bad_request
  rescue ActiveRecord::RecordNotUnique
    private_reply("Żądanie zostało już obsłużone. Użyj komendy ponownie, jeśli potrzebujesz nowego linku.")
  rescue DiscordInteractionRelay::Unavailable => error
    Rails.logger.error("Staging Discord relay unavailable: #{error.class}")
    private_reply("Logowanie do środowiska testowego jest chwilowo niedostępne. Spróbuj ponownie.")
  end

  private

  def display_name(payload, user)
    (payload.dig("member", "nick").presence || user["global_name"].presence || user["username"].presence || "Gracz").first(80)
  end

  def private_reply(content, **extra)
    render json: { type: 4, data: { content: content, flags: 64, allowed_mentions: { parse: [] } }.merge(extra) }
  end

  def verify_signature
    public_key = ENV.fetch("DISCORD_PUBLIC_KEY", "")
    signature = request.headers["X-Signature-Ed25519"].to_s
    timestamp = request.headers["X-Signature-Timestamp"].to_s
    return head :unauthorized unless public_key.match?(/\A[0-9a-f]{64}\z/i) && signature.match?(/\A[0-9a-f]{128}\z/i)
    return head :unauthorized unless timestamp.match?(/\A\d{10}\z/) && (Time.now.to_i - timestamp.to_i).abs <= 300
    return head :payload_too_large if request.raw_post.bytesize > 65_536
    Ed25519::VerifyKey.new([ public_key ].pack("H*")).verify([ signature ].pack("H*"), timestamp + request.raw_post)
  rescue Ed25519::VerifyError, ArgumentError
    head :unauthorized
  end
end
