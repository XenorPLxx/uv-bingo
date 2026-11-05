require "net/http"
require "json"
abort "Only server-specific commands are supported; omit the scope or use guild." unless ARGV.empty? || ARGV == [ "guild" ]
application = ENV.fetch("DISCORD_APPLICATION_ID")
guild = ENV.fetch("DISCORD_GUILD_ID")
path = "/applications/#{application}/guilds/#{guild}/commands"
uri = URI("https://discord.com/api/v10#{path}")
request = Net::HTTP::Post.new(uri)
request["Authorization"] = "Bot #{ENV.fetch('DISCORD_BOT_TOKEN')}"
request["Content-Type"] = "application/json"
request["User-Agent"] = "UVBingo/1.0"
data = { name: ENV.fetch("DISCORD_COMMAND", "bingo"), type: 1, description: "Link do logowania w TGA Bingo." }
request.body = JSON.generate(data)
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { |http| http.request(request) }
unless response.is_a?(Net::HTTPSuccess)
  abort "Discord registration failed (HTTP #{response.code}). Check app installation and credentials."
end
command = JSON.parse(response.body)
puts "Registered /#{command.fetch('name')} for guild #{guild} (command #{command.fetch('id')})."
