require_relative "production"
require_relative "../../lib/staging_gate"

Rails.application.configure do
  config.middleware.insert_before 0, StagingGate,
    username: ENV.fetch("STAGING_HTTP_USER"), password: ENV.fetch("STAGING_HTTP_PASSWORD")
  config.action_dispatch.default_headers["X-Robots-Tag"] = "noindex, nofollow"
end
