Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.script_src_attr :none
    policy.style_src :self
    policy.font_src :self
    policy.img_src :self, :data
    # Action Cable evaluates this in a Rack request; pages use a controller.
    policy.connect_src :self, -> { (respond_to?(:request) ? request : self).base_url.sub(/\Ahttp/, "ws") }
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  # Turbo's loading bar inserts a nonce-bearing stylesheet during navigation.
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
