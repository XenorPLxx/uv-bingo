require "digest"

class StagingGate
  def initialize(app, username:, password:)
    raise "Staging HTTP credentials must be set" if username.to_s.empty? || password.to_s.empty?
    @app, @username, @password = app, username, password
  end

  def call(env)
    path, method = env.values_at("PATH_INFO", "REQUEST_METHOD")
    return @app.call(env) if path == "/up" && %w[GET HEAD].include?(method)
    return @app.call(env) if path == "/discord/interactions" && method == "POST"
    auth = Rack::Auth::Basic::Request.new(env)
    if auth.provided? && auth.basic? && auth.credentials && auth.credentials.length == 2
      user, password = auth.credentials
      valid = same?(user, @username) & same?(password, @password)
      return @app.call(env) if valid
    end
    [ 401, { "www-authenticate" => 'Basic realm="UV Bingo staging", charset="UTF-8"',
      "content-type" => "text/plain; charset=utf-8", "cache-control" => "no-store" }, [ "Staging: wymagane hasło." ] ]
  end

  private

  def same?(a, b)
    ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(a), Digest::SHA256.hexdigest(b))
  end
end
