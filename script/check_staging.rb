require "net/http"
require "uri"
base = URI("https://bingo.testing.xenor.ovh")
def check(base, path, expected, auth: false, method: Net::HTTP::Get)
  uri = base + path
  request = method.new(uri)
  request.basic_auth(ENV.fetch("STAGING_HTTP_USER"), ENV.fetch("STAGING_HTTP_PASSWORD")) if auth
  result = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
  raise "#{path}: expected #{expected}, received #{result.code}" unless result.code.to_i == expected
  puts "#{base.host}#{path}: #{result.code} OK"
end
check(base, "/up", 200)
check(base, "/", 401)
check(base, "/cable", 401)
check(base, "/icon.svg", 401)
check(base, "/discord/interactions", 401, method: Net::HTTP::Post)
check(base, "/", 200, auth: true)
check(base, "/sign-in", 200, auth: true)
check(base, "/admin", 403, auth: true)
%w[bing.testing.xenor.ovh uv-bingo.testing.xenor.ovh].each do |hostname|
  legacy = URI("https://#{hostname}")
  check(legacy, "/", 401)
  check(legacy, "/", 200, auth: true)
  check(legacy, "/cable", 401)
end
