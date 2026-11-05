require "net/http"
require "json"
application = ENV.fetch("DISCORD_APPLICATION_ID")
guild = ENV.fetch("DISCORD_GUILD_ID")
scope = ARGV.fetch(0, "guild")
abort "Command scope must be guild or global" unless %w[guild global].include?(scope)
path = scope == "global" ? "/applications/#{application}/commands" : "/applications/#{application}/guilds/#{guild}/commands"
uri = URI("https://discord.com/api/v10#{path}")
request = Net::HTTP::Post.new(uri)
request["Authorization"] = "Bot #{ENV.fetch('DISCORD_BOT_TOKEN')}"
request["Content-Type"] = "application/json"
request["User-Agent"] = "UVBingo/1.0"
data = { name: ENV.fetch("DISCORD_COMMAND", "bingo"), type: 1, description: "Link do logowania w TGA Bingo." }
data.merge!(integration_types: [ 0 ], contexts: [ 0 ]) if scope == "global"
request.body = JSON.generate(data)
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { |http| http.request(request) }
unless response.is_a?(Net::HTTPSuccess)
  abort "Discord registration failed (HTTP #{response.code}). Check app installation and credentials."
end
command = JSON.parse(response.body)
if scope == "global"
  abort "Global command has unexpected contexts" unless command["integration_types"] == [ 0 ] && command["contexts"] == [ 0 ]
  puts "Registered /#{command.fetch('name')} globally for server installations only (command #{command.fetch('id')})."
else
  puts "Registered /#{command.fetch('name')} for guild #{guild} (command #{command.fetch('id')})."
end
