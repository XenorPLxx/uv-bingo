# UV Bingo

A Polish-language community bingo for UV o grach. Members sign in through a Discord `/bingo` command, submit predictions, and spend up to five final votes. Admins draw one shared 5×5 board and run it live with community suggestions.

## Stack

Ruby 4.0.1, Rails 8.1, PostgreSQL 17, Tailwind 4, Hotwire/Stimulus, Action Cable with Solid Cable, Kamal 2. Separate staging and production hosts follow Songbook's deployment conventions. The app and database are isolated from Songbook.

## Local development

```sh
bundle install
cp .envrc.local.example .envrc.local
# Start the dedicated database (only needed once):
docker run -d --name uv-bingo-dev-db \
  -e POSTGRES_USER=uv_bingo -e POSTGRES_PASSWORD=local-development-only \
  -p 127.0.0.1:5438:5432 -v uv-bingo-dev-data:/var/lib/postgresql/data postgres:17-alpine
set -a; source .envrc.local; set +a
bin/rails db:prepare db:seed
bin/dev
```

Open http://localhost:3100. Development/staging seeds create a clearly labeled rehearsal event with 30 example options and six synthetic voters. They never populate production and are idempotent; real events are created in `/admin`.

For local manual testing, create a participant and a single-use token through `bin/rails console`, then open `/login?token=TOKEN`. Use a Discord ID in `ADMIN_DISCORD_IDS` for admin access. There is no development bypass endpoint in the app.

## Rules

- Five vote slots per participant per event, enforced by PostgreSQL constraints and row locks.
- Adding an option and casting its first vote are one transaction.
- One vote per distinct option; votes cannot be changed or withdrawn. Duplicate vote retries are idempotent.
- Both submissions and votes require `opens_at <= now < closes_at`, stored in UTC and displayed in Europe/Warsaw.
- Duplicate text is normalized with Unicode NFKC, whitespace squishing, and case folding. Invalid/duplicate submissions spend nothing.
- Disqualified options keep their existing spent votes but cannot receive more votes or enter the draw. Admin corrections require a reason and audit record.
- Totals are visible publicly only after the voting window closes. Admins can inspect them earlier.
- Draws require at least 25 eligible options with votes and a closed window. The top 25 qualify. Equal totals are ordered using seeded SHA-256 keys; the leading option occupies position 12 (center), and the remaining 24 are independently shuffled.
- Draws store the full eligible snapshot, SHA-256 digest, seed, algorithm version, ordered option IDs, actor and timestamp. Cell text is copied at draw time. Refreshing/replaying never generates another draw. Export is available from the board page.
- During live play, each participant has one changeable `?`/`X` proposal per cell revision, independent of their voting allowance. Admin marks advance the cell revision; older proposals stay in history but stop counting.
- Only official `X` marks complete rows, columns and diagonals. Archived events are read-only.

The draw record is reproducible, not an externally tamper-proof lottery. Database operators remain trusted.

## Discord

See [Discord setup](docs/discord.md). Runtime uses signed HTTP interactions, not a persistent Gateway connection. The bot token is needed for setup/registration and is not deployed into the Rails container. Participant sessions last 30 days; login tokens last 10 minutes and require an explicit POST confirmation so previews do not consume them. The quota follows the Discord account across devices.

Only configured `ADMIN_DISCORD_IDS` have admin permissions. The database stores Discord IDs and display names, votes, and gameplay history. No email, Discord password, or message history is collected. Local environment files, login token parameters, credentials, and backups are excluded from source control/build context as applicable.

## Testing

```sh
set -a; source .envrc.local; set +a
bin/rails test
SE_AVOID_STATS=true bin/rails test:system
bin/rubocop
bundle exec brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

Tests cover budget concurrency, voting boundaries, immutable votes, duplicate handling, tie selection, repeated/concurrent draws, login token replay, Discord signatures, admin authorization, stale proposal revisions, staging Basic Auth, mobile layout, and updates between two browsers. Browser screenshots are written to `tmp/screenshots/`.

## Deployment

See [operations](docs/operations.md). Staging: https://uv-bingo.testing.xenor.ovh. Planned production: https://uv-bingo.xenor.ovh.

```sh
bin/kamal-staging accessory boot db  # first deployment only
bin/deploy-staging-safe
```

Staging requires HTTP Basic Auth for pages, assets and WebSockets. The only exceptions are `GET/HEAD /up` and `POST /discord/interactions`; the latter independently requires Discord's valid signature and a fresh timestamp. Production has no staging Basic Auth, but participant/admin authorization still applies.

The first release deploys staging only. Production requires its own Discord application, secrets, DNS and explicit deployment.
