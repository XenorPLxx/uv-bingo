require "net/http"
require "uri"

base = URI(ENV.fetch("APP_URL", "https://bingo.xenor.ovh"))
abort "Unexpected production URL" unless base.scheme == "https" && base.host == "bingo.xenor.ovh"
checks = [ [ "/up", 200 ], [ "/", 200 ], [ "/sign-in", 200 ], [ "/icon.svg", 200 ], [ "/admin", 403 ], [ "/cable", 404 ] ]
checks.each do |path, expected|
  uri = base + path
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { |http| http.get(uri.request_uri) }
  raise "#{path}: expected #{expected}, received #{response.code}" unless response.code.to_i == expected
  raise "Production unexpectedly asks for HTTP authentication" if response["www-authenticate"]
  puts "#{uri}: #{response.code} OK"
end
uri = base + "/discord/interactions"
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { |http| http.request(Net::HTTP::Post.new(uri)) }
raise "Unsigned Discord interaction was not rejected" unless response.code.to_i == 401
puts "#{uri}: 401 OK (unsigned interaction rejected)"
