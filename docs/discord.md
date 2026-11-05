# Shared Discord application

Application ID: `1567880594380030002`. The bot user is **TGA Bingo**. The same app serves both Discord servers through `https://bingo.xenor.ovh/discord/interactions`.

| Destination | Discord server | Trial channel/thread | Login website |
| --- | --- | --- | --- |
| Production | `1020591115407196201` | `1439938011650592859` | https://bingo.xenor.ovh |
| Staging | `725336022657007788` | `1567883334703390893` | https://bingo.testing.xenor.ovh |

## Installation and commands

1. Keep the app installed in the private test server. Install it in the UV community server using the `bot` and `applications.commands` scopes. Administrator and message-content permissions are unnecessary. For the trial thread, allow the app/channel permissions needed to use application commands; private threads may also require an invitation.
2. Keep the existing public app ID/key and setup bot token in local `.envrc.staging` and `.envrc.production` files, mode 600. Each destination uses its own `DISCORD_GUILD_ID`, `DISCORD_CHANNEL_ID`, `ADMIN_DISCORD_IDS`, database password and session secret. The setup bot token is never deployed into the Rails container.
3. After installation, run `bin/discord-register staging` for the private server and `bin/discord-register production` for the community server. Both use server-specific registrations; keep no global `/bingo` copy, which would produce duplicate entries. These commands upsert only this app's `/bingo` command and do not post messages.
4. After production is healthy, set its shared interactions endpoint. Source `.envrc.production` and run `bundle exec ruby script/configure_discord_endpoint.rb https://bingo.xenor.ovh/discord/interactions`. Discord verifies a signed PING before accepting the change.
5. Run `/bingo` in the appropriate server. The private reply contains a single-use login button valid for ten minutes; the website asks for confirmation of the named account. Staging additionally requires HTTP credentials. Production does not use Basic Auth.

Community installation may be completed after the website launch; register its server-specific command afterward. Both servers currently have exactly one direct `/bingo` command and there is no global copy. Until installation and registration are complete, community members can view the trial pages but cannot obtain new production login links through `/bingo`.

An archived thread must be reopened before members can use commands in it. Refresh Discord after changing installation or command settings. Reinstalling the staging app is unnecessary when its existing `/bingo` command is visible.

## Routing and verification

Discord configures one interaction URL per application. Production verifies the Ed25519 signature over the exact body/timestamp and enforces the timestamp window before routing. Community-server commands create production accounts/tokens normally. Only the configured private-server `/bingo` command is relayed to staging, preserving signed bytes and signature headers. Staging verifies the signature again and deduplicates the interaction in its own database.

Relay requests use HTTPS, no redirects/retries, short network timeouts and a two-second total deadline. Only an ephemeral response is accepted. A staging outage returns a private unavailable message; community commands continue locally. Unknown servers/commands and invalid signatures are rejected. Production does not create accounts or login tokens for relayed staging commands.

Returning members reuse the account identified by their Discord ID and receive a new login token for each new interaction. PostgreSQL's unique index, rather than a uniqueness validator before insertion, resolves concurrent account creation for `create_or_find_by!`.

`/bingo` uses HTTP interactions rather than a Gateway connection; the bot can appear offline while commands work. The webhook is the only app route that bypasses staging HTTP authentication and always verifies Discord signatures. Signed PING requests have no server ID and are handled before guild routing.

Legacy links on `bing.testing.xenor.ovh` and `uv-bingo.testing.xenor.ovh` remain usable, but browser sessions are scoped to each hostname. Use a fresh `/bingo` link for `bingo.testing.xenor.ovh`.
