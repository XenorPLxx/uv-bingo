Rails.application.config.filter_parameters += [ :token, :signature, :authorization, :pending_login_token ]
Rails.application.config.action_dispatch.default_headers.merge!(
  "Referrer-Policy" => "no-referrer",
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=()"
)
Rails.application.config.session_store :cookie_store, key: "_uv_bingo_session",
  secure: !Rails.env.local?, httponly: true, same_site: :lax
