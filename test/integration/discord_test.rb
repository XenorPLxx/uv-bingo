require "test_helper"
require "active_support/testing/constant_stubbing"

class DiscordTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::ConstantStubbing
  setup do
    @key = Ed25519::SigningKey.generate
  end

  test "Discord ping signature and timestamp must be valid" do
    with_env DISCORD_PUBLIC_KEY: @key.verify_key.to_bytes.unpack1("H*") do
      send_interaction({ type: 1 })
      assert_response :success
      assert_equal 1, response.parsed_body["type"]
      send_interaction({ type: 1 }, timestamp: 10.minutes.ago.to_i.to_s)
      assert_response :unauthorized
      send_interaction({ type: 1 }, signing_key: Ed25519::SigningKey.generate)
      assert_response :unauthorized
      post "/discord/interactions", params: { type: 1 }, as: :json
      assert_response :unauthorized
    end
  end

  test "guild command returns ephemeral login and deduplicates Discord retries" do
    with_env DISCORD_PUBLIC_KEY: @key.verify_key.to_bytes.unpack1("H*"), DISCORD_GUILD_ID: "guild-123", APP_URL: "https://bingo.example", DISCORD_COMMAND: "bingo" do
      payload = { id: "interaction-1", type: 2, guild_id: "guild-123", data: { name: "bingo" }, member: { user: { id: "voter-123", username: "Tester" } } }
      send_interaction(payload)
      assert_response :success
      assert_equal 64, response.parsed_body.dig("data", "flags")
      assert_match %r{\Ahttps://bingo.example/login\?token=}, response.parsed_body.dig("data", "components", 0, "components", 0, "url")
      assert_equal 1, LoginToken.count
      send_interaction(payload)
      assert_equal 1, LoginToken.count
      send_interaction(payload.merge(id: "interaction-2", guild_id: "other-guild"))
      assert_response :forbidden
      assert_equal 1, LoginToken.count
    end
  end

  test "missing application URL is logged and does not issue an unusable token" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    Rails.logger.broadcast_to(logger)
    with_env DISCORD_PUBLIC_KEY: @key.verify_key.to_bytes.unpack1("H*"), DISCORD_GUILD_ID: "guild-123", APP_URL: nil do
      payload = { id: "missing-config", type: 2, guild_id: "guild-123", data: { name: "bingo" }, member: { user: { id: "voter-123" } } }
      assert_no_difference [ "LoginToken.count", "Participant.count" ] do
        send_interaction(payload)
        assert_response :success
        assert_equal 64, response.parsed_body.dig("data", "flags")
        assert_match "chwilowo niedostępne", response.parsed_body.dig("data", "content")
      end
      assert_includes output.string, "APP_URL is missing"
      send_interaction(payload.except(:id))
      assert_response :bad_request
    end
  ensure
    Rails.logger.stop_broadcasting_to(logger) if logger
  end

  test "shared app relays only verified staging commands and keeps production tokens local" do
    forwarded = []
    relay = Class.new(DiscordInteractionRelay)
    relay.define_singleton_method(:call) do |**request|
      forwarded << request
      { type: 4, data: { flags: 64, content: "Odpowiedź stagingu" } }
    end
    with_env DISCORD_PUBLIC_KEY: @key.verify_key.to_bytes.unpack1("H*"), DISCORD_GUILD_ID: "production-guild",
      DISCORD_STAGING_GUILD_ID: "staging-guild", APP_URL: "https://bingo.example" do
      stub_const(Object, :DiscordInteractionRelay, relay) do
        payload = { id: "stage-command", type: 2, guild_id: "staging-guild", data: { name: "bingo" }, member: { user: { id: "stage-user" } } }
        assert_no_difference [ "Participant.count", "LoginToken.count" ] do
          send_interaction(payload)
          assert_response :success
          assert_equal 64, response.parsed_body.dig("data", "flags")
        end
        assert_equal JSON.generate(payload), forwarded.sole.fetch(:body)
        request = forwarded.sole
        assert @key.verify_key.verify([ request.fetch(:signature) ].pack("H*"), request.fetch(:timestamp) + request.fetch(:body))
        send_interaction(payload, signing_key: Ed25519::SigningKey.generate)
        assert_response :unauthorized
        send_interaction(payload.merge(guild_id: "unknown-guild"))
        assert_response :forbidden
        send_interaction(payload.merge(data: { name: "other" }))
        assert_response :forbidden
        assert_equal 1, forwarded.size
        send_interaction(payload.merge(id: "production-command", guild_id: "production-guild"))
        assert_response :success
        assert_equal 1, LoginToken.count
        assert_match %r{\Ahttps://bingo.example/login\?token=}, response.parsed_body.dig("data", "components", 0, "components", 0, "url")
        assert_equal 1, forwarded.size
      end
    end
  end

  test "unavailable staging returns a private error without creating production accounts" do
    relay = Class.new(DiscordInteractionRelay)
    relay.define_singleton_method(:call) { |**_request| raise DiscordInteractionRelay::Unavailable }
    with_env DISCORD_PUBLIC_KEY: @key.verify_key.to_bytes.unpack1("H*"), DISCORD_GUILD_ID: "production-guild", DISCORD_STAGING_GUILD_ID: "staging-guild" do
      stub_const(Object, :DiscordInteractionRelay, relay) do
        assert_no_difference [ "Participant.count", "LoginToken.count" ] do
          send_interaction({ id: "unavailable", type: 2, guild_id: "staging-guild", data: { name: "bingo" }, member: { user: { id: "stage-user" } } })
          assert_response :success
          assert_equal 64, response.parsed_body.dig("data", "flags")
          assert_match "chwilowo niedostępne", response.parsed_body.dig("data", "content")
        end
      end
    end
  end

  private

  def send_interaction(payload, timestamp: Time.now.to_i.to_s, signing_key: @key)
    body = JSON.generate(payload)
    signature = signing_key.sign(timestamp + body).unpack1("H*")
    post "/discord/interactions", params: body, headers: { "CONTENT_TYPE" => "application/json", "X-Signature-Ed25519" => signature, "X-Signature-Timestamp" => timestamp }
  end
end
