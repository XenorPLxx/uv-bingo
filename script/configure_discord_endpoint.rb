require "net/http"
require "json"
endpoint = ARGV.fetch(0)
abort "Endpoint must use HTTPS" unless endpoint.start_with?("https://")
uri = URI("https://discord.com/api/v10/applications/@me")
request = Net::HTTP::Patch.new(uri)
request["Authorization"] = "Bot #{ENV.fetch('DISCORD_BOT_TOKEN')}"
request["Content-Type"] = "application/json"
request.body = JSON.generate(interactions_endpoint_url: endpoint)
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(request) }
abort "Endpoint update failed (HTTP #{response.code}): #{JSON.parse(response.body)['message']}" unless response.is_a?(Net::HTTPSuccess)
value = JSON.parse(response.body).fetch("interactions_endpoint_url")
abort "Unexpected endpoint returned" unless value == endpoint
puts "Discord verified and saved interactions endpoint: #{value}"
