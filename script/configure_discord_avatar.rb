require "net/http"
require "json"
require "base64"

def discord_request(method, path, payload = nil)
  uri = URI("https://discord.com/api/v10#{path}")
  request = method.new(uri)
  request["Authorization"] = "Bot #{ENV.fetch('DISCORD_BOT_TOKEN')}"
  request["Content-Type"] = "application/json"
  request["User-Agent"] = "UVBingo/1.0"
  request.body = JSON.generate(payload) if payload
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(request) }
  abort "Discord request failed (HTTP #{response.code}) for #{path}." unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

image_file = ARGV.fetch(0, File.expand_path("../docs/branding/discord-avatar.png", __dir__))
png = File.binread(image_file)
abort "Expected a PNG image" unless png.start_with?("\x89PNG\r\n\x1a\n".b)
application = discord_request(Net::HTTP::Get, "/applications/@me")
bot = discord_request(Net::HTTP::Get, "/users/@me")
expected_id = ENV.fetch("DISCORD_APPLICATION_ID")
abort "Token belongs to a different application" unless application.fetch("id") == expected_id
abort "Expected this application's bot account" unless bot["bot"] && bot.fetch("id") == application.dig("bot", "id")

image_data = "data:image/png;base64,#{Base64.strict_encode64(png)}"
updated_app = discord_request(Net::HTTP::Patch, "/applications/@me", { icon: image_data })
abort "Application icon was not saved" unless updated_app["icon"] && discord_request(Net::HTTP::Get, "/applications/@me")["icon"] == updated_app["icon"]
puts "Verified Discord application icon for #{expected_id}."
updated_bot = discord_request(Net::HTTP::Patch, "/users/@me", { avatar: image_data })
abort "Bot avatar was not saved" unless updated_bot["avatar"] && discord_request(Net::HTTP::Get, "/users/@me")["avatar"] == updated_bot["avatar"]
puts "Verified Discord bot avatar for #{bot.fetch('id')}."
