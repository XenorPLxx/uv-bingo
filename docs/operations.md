# Operations

## Hosts and isolation

- Staging: `xenor@192.168.2.73`, `bingo.testing.xenor.ovh`. The previous `bing.testing.xenor.ovh` and `uv-bingo.testing.xenor.ovh` addresses remain compatibility aliases with the same HTTP authentication.
- Production: `ubuntu@5.135.141.150`, `bingo.xenor.ovh`.
- Registry image: `gitea.xenor.ovh/xenor/uv-bingo`.
- Accessory: `uv-bingo-db`, PostgreSQL 17, its own persistent data directory and credentials.
- Databases: `uv_bingo_staging` / `uv_bingo_production`.
- Rails: one Puma worker; Solid Cable uses the app's PostgreSQL database and trims messages after an hour. Durable board/proposal history is stored independently of Cable messages.

## First staging deploy

Copy `.envrc.staging.example` to `.envrc.staging`, generate independent secrets, and set mode 600. Runtime needs `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, `ADMIN_DISCORD_IDS`, and staging HTTP username/password. Registry credentials can use the existing registry account. The wrapper loads this file automatically.

The staging hostname must resolve to the staging host's public ingress and port 443 must reach the existing Kamal proxy. Avoid changing or rebooting shared proxy settings for unrelated applications.

```sh
bin/kamal-staging accessory boot db
bin/deploy-staging-safe
bin/discord-register staging
```

The entrypoint runs `db:prepare` before Rails starts; do not run an additional migration step after traffic has switched. The wrapper then checks for pending migrations and probes HTTP access boundaries. A brand-new staging database is seeded with a rehearsal event. `/up` returns basic boot health without app data.

## Event rehearsal

Use the event links above the hero/board to switch between voting and live events. Multiple voting windows can overlap; each participant has a separate five-vote allowance in each event.

Proposal search updates after a 300 ms typing pause. Enter or **Szukaj** searches immediately; clearing the field restores all proposals. Filtering preserves input focus, proposal drafts and scroll position. The current filter is included in the page URL for sharing or reloading.

Public pages render [Open Graph](https://ogp.me/) and X large-image card metadata in the initial HTML. Event previews use the event title and description, with the community artwork as the image. Absolute preview URLs use `APP_URL`; search parameters and login tokens are excluded. The homepage keeps its root canonical URL, while presentation/reveal views point to their event page. Account and admin pages use generic site metadata. The artwork is served through the normal asset pipeline with its dimensions and alternative text included in the tags.

1. `/bingo` in the configured test channel, open the private link, enter staging HTTP credentials, confirm login.
2. Add an option and vote. Each action uses one of five active slots. Withdraw a vote to free a slot; its proposal remains available. Each participant can create at most 20 proposals per event, including withdrawn, excluded and merged proposals. Reaching that cap still allows voting on existing proposals. Choices freeze when voting closes.
3. To combine duplicates, open the event in `/admin`, expand **Połącz propozycje** under **Propozycje i wyniki**, choose the source and retained proposal, and enter a reason. The retained wording stays; double voters get one slot back. Restore excluded proposals before merging them. The source remains in the moderation history.
4. Open `/admin`; choose the rehearsal event and move its closing date into the past (after its opening date).
5. Confirm the draw once voting is closed and at least 25 eligible proposals have votes; the button shows that count and stays disabled until both conditions hold. Record the reveal screen. Replay restarts the animation of the saved result, including during an earlier replay; reduced-motion preferences show the result immediately with an explanation.
6. Start the live event from admin. Open presentation mode in another browser.
7. Click the `?` / `X` counters on the left to suggest a mark. Admins use the colored buttons on the right for official decisions. Both work in presentation mode; clicking a selected mark again clears it. Verify the viewer updates and old proposals stop counting.
8. Archive the event. Create a new rehearsal event for another run; never reroll the same event.

The **Wydarzenie testowe** checkbox only adds a visible label. Such events are public and use the same voting and draw rules; the checkbox does not populate sample proposals.

To remove an unwanted event, open it in `/admin` and choose **Usuń wydarzenie**. Review the counts, type the event's slug and submit **Usuń trwale**. This permanently removes the event's votes, options, draw, board, suggestions and audit history. Participant accounts and data from other events remain. Archiving keeps a board available for reading; deletion removes it.

Production should use a fresh event with real options/votes, not the seeded rehearsal data.

## Backup and restore

Production uses the same server backup layout as the other apps. Install or update its daily job with:

```sh
bin/install-prod-backup-cron
```

The installer places `script/backup_production_db.sh` at `/home/ubuntu/uv-bingo/db_backup_production.sh`, verifies one backup, and installs a single `ubuntu` cron entry at 04:30 UTC, tagged `uv-bingo-prod-db-backup`. Other apps' cron entries remain unchanged. Normal application deployments do not run a backup.

Dumps are gzip-compressed SQL files at `/home/ubuntu/backups/uv-bingo/prod_dump_*.sql.gz`, with seven-day retention. The job locks against overlapping runs, writes to a private temporary file, validates the gzip stream and SQL header, then publishes the completed dump. Failed backups leave existing dumps intact; pruning only runs after success. Cron output goes to `/home/ubuntu/backups/uv-bingo/backup.log`. The previous `uv-bingo-production-backup` cron entry is replaced; older dumps under `/home/ubuntu/backups/uv-bingo-production/daily` are retained.

On Unraid srv01 (`root@192.168.2.42`), the existing **rsync_daily** user script includes **Bingo-daily** alongside the other apps. It pulls `ovh02:~/backups/uv-bingo/` into `/mnt/user/Backups/Bingo/`, using `/mnt/user/appdata/ssh/config` and the existing daily 03:00 local schedule. As with the other database backup jobs, it does not use `--delete`, so server retention does not delete older copies on srv01.

Optional manual backups:

```sh
bin/backup-production-server  # write another SQL gzip dump on production
bin/backup-db production     # download a custom-format dump into local backups/
bin/backup-db staging
```

Local `backups/` is ignored by Git. Those custom-format dumps use PostgreSQL 17+ `pg_restore`; server/srv01 SQL dumps use `gzip -dc DUMP.sql.gz | psql -v ON_ERROR_STOP=1 -d RESTORE_DATABASE`. Verify backups by restoring into a separate temporary database and checking row counts and saved draws. Never restore over an active event merely to verify a backup.

## Rollback and diagnostics

```sh
bin/kamal-staging app details
bin/kamal-staging app logs --since 10m
bin/kamal-staging rollback PREVIOUS_IMAGE_VERSION
bin/check-staging-health
```

Rollback changes the app image, not the database. Future schema migrations must remain compatible with the previous app version during a rolling deployment. Test the rollback path when there is a prior working version; a brand-new first release has none.

Board clients resync on reconnect, when the tab becomes visible, and every 15 seconds. Voting pages refetch when a committed vote, withdrawal or new proposal is broadcast, on reconnect and when the tab becomes visible; they poll every 15 seconds only while the socket is down or a search has failed, and otherwise resync once a minute. Polls send the current phase and revision; unchanged boards return only those values without rendering HTML. Responses remain uncached. Failed broadcasts don't undo committed marks. A visible status explains lost connectivity; no write is queued offline. Public streams carry only change notifications; personalized HTML is fetched through normal authorized sessions. Voting refreshes preserve sidebar scroll and unfinished proposal text and keep the list in place while its top or most of the screen is unchanged, so only proposals that changed rank move. They slide into place and changed totals pulse; reduced motion disables both. Server-side revision checks reject stale board writes.

The content security policy permits local assets, nonce-authorized importmap scripts/Turbo loading-bar styles and the current host's WebSocket endpoint. It blocks inline script attributes, plugins and embedding in other sites. Policy configuration follows the [Rails security guide](https://guides.rubyonrails.org/security.html#content-security-policy-header). A missing Discord `APP_URL` logs a configuration error and returns a private unavailable message before issuing a login token.

## Production deployment and community trial

DNS `bingo.xenor.ovh` points to `5.135.141.150`. Keep separate secrets in the ignored, mode-600 `.envrc.production`; production has no staging HTTP-authentication middleware. The shared Discord app routes the two server IDs to separate databases/sites as described in [Discord setup](discord.md).

```sh
bin/kamal-production accessory boot db  # once, on a new host
bin/deploy-production-safe
bin/install-prod-backup-cron            # initial setup or backup-script changes
bin/kamal-production app exec --reuse "bin/rails runner script/prepare_trial.rb"
```

Trial setup is explicit and idempotent; it is not part of normal deployment or database seeds. It creates two public, labeled test events:

- `/e/proba-glosowania`: voting opens immediately for seven days, with 30 example proposals and zero example votes, so community votes start from zero. Participants can add their own proposals and use/withdraw their five votes.
- `/e/plansza-testowa`: a saved 25-cell example draw in the live phase, with sample votes used only for this demo. Signed-in members can suggest `?`/`X`, and configured admins can mark fields. `/e/plansza-testowa/presentation` is its screenshot/presentation view.

Rerunning setup preserves existing votes, dates, draw records and marks. Adjust trial dates in admin when needed; archive/delete the test events when the trial ends, then create a fresh real event for TGA.

After the bot is installed in the UV community server, run `bin/discord-register production` and test `/bingo` in thread `1439938011650592859`. Each server has its own registration; keep no global copy, which would appear as a second command. The website and public demo can be released before installation; new community sign-ins require the server installation and command registration.
