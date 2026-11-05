require "test_helper"
require Rails.root.join("lib/staging_gate")

class StagingGateTest < ActiveSupport::TestCase
  test "protects pages assets and cable with only two exact exceptions" do
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }
    gate = StagingGate.new(app, username: "tester", password: "a-long-password")
    [ "/", "/admin", "/cable", "/assets/banner.png", "/up/", "/discord/interactions/" ] .each do |path|
      assert_equal 401, gate.call(Rack::MockRequest.env_for(path))[0], path
    end
    assert_equal 200, gate.call(Rack::MockRequest.env_for("/up"))[0]
    assert_equal 200, gate.call(Rack::MockRequest.env_for("/discord/interactions", method: "POST"))[0]
    assert_equal 401, gate.call(Rack::MockRequest.env_for("/discord/interactions"))[0]
    assert_equal 401, gate.call(Rack::MockRequest.env_for("/up", method: "POST"))[0]
    assert_equal 200, gate.call(Rack::MockRequest.env_for("/cable", "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("tester", "a-long-password")))[0]
    assert_raises(RuntimeError) { StagingGate.new(app, username: "", password: "") }
  end
end
