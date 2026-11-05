# Discord setup

1. Create a separate Discord application per environment. Record application ID and public key.
2. Store its bot token in the local `.envrc.staging` or `.envrc.production`, together with `DISCORD_APPLICATION_ID`, `DISCORD_PUBLIC_KEY`, `DISCORD_GUILD_ID`, `DISCORD_CHANNEL_ID`, and comma-separated `ADMIN_DISCORD_IDS`.
3. Install it in the intended server using the `bot` and `applications.commands` scopes. No administrator or message-content permissions are needed.
4. Run `bin/discord-register staging`. It upserts the `/bingo` command in this app's server; it does not modify other apps' commands or post messages.
5. After the website is deployed, set **Interactions Endpoint URL** to `https://uv-bingo.testing.xenor.ovh/discord/interactions`. This can be done in the Developer Portal or with `script/configure_discord_endpoint.rb` using the private bot token. Discord must validate the endpoint's signed PING.
6. In the test channel, run `/bingo`. The private reply contains a 10-minute single-use login button. The website asks you to confirm the named account before creating a browser session.

Staging application: `1567880594380030002`.
Test guild: `725336022657007788`.
Test channel: `1567883334703390893`.

The webhook URL is the only application route that bypasses staging Basic Auth; it always verifies the Ed25519 signature over the exact request body and timestamp, then rejects interactions from other guilds. Discord's initial PING has no guild and is handled after signature verification.

`/bingo` is an HTTP interaction command, so the bot can appear offline in Discord while the command remains functional. Browser sign-in requires the additional staging HTTP credentials from the local environment file.

A bot token is a setup credential. Runtime only receives the application public key and public IDs. Never paste tokens into chat, commit them, or include them in URLs.
