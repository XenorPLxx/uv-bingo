# Operations

## Hosts and isolation

- Staging: `xenor@192.168.2.73`, `uv-bingo.testing.xenor.ovh`.
- Production configuration: `ubuntu@5.135.141.150`, `uv-bingo.xenor.ovh`.
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

1. `/bingo` in the configured test channel, open the private link, enter staging HTTP credentials, confirm login.
2. Add an option and vote. Each action uses one of five active slots. Withdraw a vote to free a slot; its proposal remains available. Choices freeze when voting closes.
3. Open `/admin`; choose the rehearsal event and move its closing date into the past (after its opening date).
4. Confirm the draw. Record the reveal screen; replay displays the saved result.
5. Start the live event from admin. Open presentation mode in another browser.
6. Click the `?` / `X` counters on the left to suggest a mark. Admins use the colored buttons on the right for official decisions. Both work in presentation mode; clicking a selected mark again clears it. Verify the viewer updates and old proposals stop counting.
7. Archive the event. Create a new rehearsal event for another run; never reroll the same event.

Production should use a fresh event with real options/votes, not the seeded rehearsal data.

## Backup and restore

```sh
bin/backup-db staging
```

Backups are custom-format `pg_dump` files in local ignored `backups/`. Verify with a PostgreSQL 17+ `pg_restore --list`; restore into a separate temporary database and check row counts before treating a backup as verified. Never restore over an active event merely to verify a backup.

For event-day operations, take a backup before the draw and before the live session. Configure server-side scheduled backups and off-host retention before production; the first staging release includes the on-demand backup and restore-check procedure.

## Rollback and diagnostics

```sh
bin/kamal-staging app details
bin/kamal-staging app logs --since 10m
bin/kamal-staging rollback PREVIOUS_IMAGE_VERSION
bin/check-staging-health
```

Rollback changes the app image, not the database. Future schema migrations must remain compatible with the previous app version during a rolling deployment. Test the rollback path when there is a prior working version; a brand-new first release has none.

Clients resync on reconnect, when the tab becomes visible, and every 15 seconds. Failed broadcasts don't undo committed marks. A visible status explains lost connectivity; no write is queued offline. Public streams carry only change notifications; personalized HTML is fetched through normal authorized sessions. Opening a cell dialog temporarily delays resync to preserve the user's interaction, and server-side revision checks reject stale writes.

## Production preparation

Production config is checked in but is not deployed by staging commands. Provision separate secrets, install the production Discord application in the community server, configure the final domain, backups and endpoint, and deploy only when production is authorized.
