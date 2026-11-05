require "test_helper"

class DiscordInteractionRelayTest < ActiveSupport::TestCase
  class FakeHTTP
    attr_reader :host, :port, :options, :sent_request

    def initialize(code: "200", body: JSON.generate(type: 4, data: { flags: 64, content: "Prywatny link" }), failure: nil, delay: 0)
      @response = Struct.new(:code, :body).new(code, body)
      @failure, @delay = failure, delay
    end

    def start(host, port, **options)
      @host, @port, @options = host, port, options
      raise @failure if @failure
      sleep @delay if @delay.positive?
      yield self
    end

    def request(request)
      @sent_request = request
      @response
    end
  end

  test "preserves signed bytes and headers and returns only an ephemeral response" do
    transport = FakeHTTP.new
    body = "{ \"type\": 2, \"message\": \"Zażółć\" }"
    with_env DISCORD_STAGING_INTERACTIONS_URL: "https://staging.example/discord/interactions" do
      data = DiscordInteractionRelay.call(body: body, signature: "signed-by-discord", timestamp: "1234567890", http: transport)
      assert_equal "staging.example", transport.host
      assert_equal 443, transport.port
      assert transport.options[:use_ssl]
      assert_equal 0, transport.options[:max_retries]
      assert_equal body.b, transport.sent_request.body.b
      assert_equal "signed-by-discord", transport.sent_request["X-Signature-Ed25519"]
      assert_equal "1234567890", transport.sent_request["X-Signature-Timestamp"]
      assert_equal 64, data.dig("data", "flags")
    end
  end

  test "rejects unsafe endpoints failed responses public replies and transport errors" do
    [ "http://staging.example/discord/interactions", "https://user:password@staging.example/discord/interactions", "https://staging.example/other", "https://staging.example/discord/interactions?extra=1" ].each do |url|
      transport = FakeHTTP.new
      with_env DISCORD_STAGING_INTERACTIONS_URL: url do
        assert_raises(DiscordInteractionRelay::Unavailable) { relay(transport) }
        assert_nil transport.host
      end
    end
    responses = [
      FakeHTTP.new(code: "403"), FakeHTTP.new(code: "302"), FakeHTTP.new(body: "not-json"),
      FakeHTTP.new(body: JSON.generate(type: 4, data: { flags: 0 })),
      FakeHTTP.new(body: "x" * 65_537), FakeHTTP.new(failure: SocketError.new("unreachable"))
    ]
    with_env DISCORD_STAGING_INTERACTIONS_URL: "https://staging.example/discord/interactions" do
      responses.each { |transport| assert_raises(DiscordInteractionRelay::Unavailable) { relay(transport) } }
    end
  end

  test "bounds total relay time below Discord's initial response deadline" do
    with_env DISCORD_STAGING_INTERACTIONS_URL: "https://staging.example/discord/interactions" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(DiscordInteractionRelay::Unavailable) { relay(FakeHTTP.new(delay: 4)) }
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
    end
  end

  private

  def relay(http)
    DiscordInteractionRelay.call(body: "{}", signature: "signature", timestamp: "1234567890", http: http)
  end
end
