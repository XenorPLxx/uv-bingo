# First staging release — 5 November 2026

Staging: https://bingo.testing.xenor.ovh

Verified:

- Application suite: 25 tests / 128 assertions covering votes, concurrent requests, draw reproducibility, login tokens, Discord signatures, permissions, and staging access rules.
- Chrome system tests: 2 tests / 18 assertions, including five final votes, mobile overflow, a live update to a second browser, and presentation overflow with realistic and maximum-length option text.
- Rails eager loading and RuboCop pass. Brakeman reports no warnings. Ruby dependency and importmap audits report no known vulnerabilities.
- Pages, assets and `/cable` reject requests without staging Basic Auth. The minimal health check remains available. Unsigned webhook requests are rejected.
- Discord validated the public interaction endpoint. The user confirmed successful `/bingo` sign-in from the configured test channel.
- A separate live verification board accepted 50 simultaneous WebSocket subscriptions in approximately 4.9 seconds. All 50 received a committed board update through Solid Cable/PostgreSQL.
- Saved draw records survived the final Kamal redeploy unchanged. The deployed version can be inspected with `bin/kamal-staging app details`.
- A staging backup restored successfully into an isolated local PostgreSQL 17 database: one event, 30 options, 30 votes in that snapshot. The temporary restore database was removed afterward.

Rehearsal voting event: `/e/tga-2026-proba`.
Live verification board: `/e/kontrola-wdrozenia`.

These are clearly labeled test events. Production has configuration only and has not been deployed. Source is a separate local Git repository; no remote source repository was created.

## Voting and board update — 5 November 2026

- Multiple events are linked from the voting and board pages; voting allowances remain independent per event.
- Participants can withdraw votes until the deadline, including their initial vote on their own proposal. Proposals remain available; a freed slot can be reused without exceeding five active votes.
- Compact option cards remove the repeated equal-weight caption, and larger text improves readability.
- Inline community suggestions and colored admin decisions work in both board views. Clicking the selected mark again clears it; the board updates without navigation or confirmation dialogs.
- Application suite: 31 tests / 188 assertions. Chrome suite: 2 tests / 39 assertions, including withdrawal at the limit, two-browser live updates, role-specific controls, and long text fitting on desktop and narrow screens.
- RuboCop passes; Brakeman reports no warnings. No database migration is required.
- Deployed application commit: `bf32d77`. Staging access checks passed for pages, assets, Cable and the Discord endpoint.
- A temporary staging participant successfully cast and withdrew a vote while preserving the option, then suggested and cleared a mark from presentation mode. A separate browser received both live updates. Event navigation exposes the live test board, and the saved draw record remained unchanged. The temporary account, login tokens and test activity were removed afterward.

## Copy, compact proposal list and Discord avatar — 5 November 2026

- Replaced slogans with the event title and concise descriptions of voting, proposal submission, sign-in and board generation. Removed the brand tagline and shortened the hero.
- Proposals use one compact row per item on every screen size, with the vote action on the right. Text wraps on narrow screens and mobile actions retain a 44px touch target.
- Application suite: 31 tests / 188 assertions. Existing Chrome journeys: 2 tests / 39 assertions, including voting, withdrawal, desktop/mobile layout and live updates. RuboCop passes.
- Generated `docs/branding/discord-avatar.png` with the built-in image_gen tool; saved the full prompt alongside it. Applied and read back both the staging Discord application icon and bot avatar successfully.

## Copy audit follow-up — 5 November 2026

- Checked the deployed homepage, voting event, sign-in, live board, presentation and draw reveal: the removed slogans were absent. Checked stored event descriptions and authenticated admin pages separately.
- Found and corrected the Discord login reply and command description, admin wording for excluded votes, and remaining promotional status labels. Admin instructions now explicitly allow withdrawing votes until the deadline.
- Disabled Turbo page snapshots so Turbo navigation does not restore old page text or personalized vote counts from its snapshot cache.

## Proposal merging — 5 November 2026

- Added an admin merge form under **Propozycje i wyniki → Połącz propozycje**. The admin chooses the source and retained proposal and supplies a reason.
- A merge transfers the union of voters. The retained vote wins for duplicate voters; removing their source vote returns exactly one quota slot. Other votes keep their slot and timestamp. Source wording/authorship remains in moderation history, and repeated merges redirect older aliases to the final retained proposal.
- Merging is limited to eligible proposals from the same event, before a draw. Excluded proposals must be restored first. A saved draw cannot be changed. The source, target, reason, moved votes and refunded slots are recorded in the audit history.
- Voting pages refresh on moderation revisions, while protecting text being edited. Cached voting requests resolve a merged proposal to the retained proposal.
- Application suite: 39 tests / 286 assertions. Chrome system suite: 3 tests / 53 assertions. Coverage includes quota refunds and reuse, concurrent merges/voting, chained merges, transaction rollback, permissions, draw snapshots and a second browser refreshing after a merge. RuboCop passes; Brakeman reports no warnings.
- The nullable merge reference is an additive migration. A staging database backup was taken before deployment.

## Vote totals and proposal ordering — 5 November 2026

- Proposals are ordered by descending vote count, with stable creation-time/ID order for display ties. Totals are public during voting and replace sequence numbers in the left column, including on mobile. The duplicate totals beside vote actions were removed.
- Casts and withdrawals advance the event revision so open pages refresh their totals and ordering. Refresh is deferred while a form is submitting or a text field is being edited. Seeded draw tie-breaking remains independent of the display order.
- Application suite: 40 tests / 303 assertions. Chrome suite: 3 tests / 53 assertions. RuboCop passes.

## Domain change — 5 November 2026

- Staging now uses `bing.testing.xenor.ovh` for the application URL and Discord interaction/login URLs. The previous `uv-bingo.testing.xenor.ovh` hostname remains a compatibility alias. Both hosts are covered by HTTPS, staging HTTP authentication, Rails host authorization and allowed Cable origins.
- Production configuration and Rails fallback URLs target `bing.xenor.ovh` for the later production release. Production has not been deployed.
- Validated both destination configurations with Kamal. Existing staging-authentication, Discord and website integration checks pass; RuboCop passes.

## Event deletion and test-event explanation — 5 November 2026

- Added **Usuń wydarzenie** to the admin event header. A separate review page lists the affected proposal, vote, draw, cell, mark-suggestion and audit-history counts. Permanent deletion requires typing the exact event slug.
- Event-scoped cleanup runs under the event lock in one transaction, including merged proposals and immutable draw/audit records. Other events, participant accounts, sessions and login tokens remain. Deleted-board viewers return to the homepage with an explanation.
- Renamed the rehearsal checkbox and public badge to **Wydarzenie testowe**. The creation form explains that it is a visible label only: these events are public and follow the same voting and drawing rules. It does not seed example data.
- Application suite: 44 tests / 359 assertions. Chrome suite: 4 tests / 65 assertions. Coverage includes typed confirmation, permissions, scoped cleanup, rollback and live viewer navigation after deletion. RuboCop passes; Brakeman reports no warnings. A staging database backup was taken before deployment.

## Voting without page jumps — 5 November 2026

- Voting, withdrawals and proposal submissions update the proposal list, ballot and available allowance in place. Success and error messages appear immediately above **Propozycje**, including the HTML fallback. Search filters remain active.
- Background revision updates replace voting fragments instead of navigating. Viewport anchoring keeps neighbouring proposals steady when the sorted order changes. Desktop sidebar scroll and unfinished proposal text are retained, including when the five-vote limit temporarily removes the proposal form.
- Application suite: 46 tests / 398 assertions. Chrome suite: 5 tests / 93 assertions. Coverage includes desktop/mobile scroll position, no navigation, background sorting, sidebar scroll, draft/preview restoration, JSON validation errors and local HTML messages. RuboCop passes; Brakeman reports no warnings. No database migration is required.

## Review fixes and reveal replay — 5 November 2026

- Added a 20-proposal lifetime cap per participant/event under the existing event and participant locks. Withdrawn, excluded and merged proposals count; voting on existing proposals remains available. The UI displays the authored count and disables submission at the limit.
- Rechecked in-place voting, withdrawal from the list and sidebar, and background sorting. Existing viewport/draft regression tests continue to pass.
- Invalid admin creation/settings/moderation/merge submissions keep their inputs and display errors in admin. Invalid settings are rendered separately from the persisted event, so missing dates do not break the surrounding page. Other admin action errors return to the admin event page; board mark errors retain the board flow.
- The draw button and draw service share the eligible-with-votes scope. The admin page shows the qualifying count and requires both a closed voting window and 25 qualifying proposals. Stale/foreign/unavailable voting options return a local validation error instead of a 404.
- Enabled CSP for local assets, nonce-authorized scripts/Turbo loading-bar styles and the same-host WebSocket endpoint, including Action Cable's Rack request context. Missing Discord `APP_URL` is logged and returns a private unavailable reply without creating a token/account. Unchanged board polls return only phase/revision and skip HTML rendering; removed the unused hello controller.
- Reveal replay starts fresh staggered animations, including if replayed mid-animation. Saved draw records and cell positions remain unchanged. Reduced-motion settings reveal immediately and explain why there is no animation.
- Application suite: 57 tests / 551 assertions. Chrome suite: 7 tests / 129 assertions. Coverage includes proposal-cap races, moderation/merge history counts, preserved admin forms, draw prerequisites, stale options, CSP/WebSocket/loading-bar handling, metadata-only polling, actual replay/restart, reduced motion and unchanged saved draws. RuboCop passes; Brakeman reports no warnings. No database migration is required.

## Debounced proposal search — 5 November 2026

- Search filters in place after a 300 ms typing pause; Enter/the search button bypass the delay. Clearing the native search field restores the list. The query is kept in the URL and submitted vote/proposal forms; the normal GET form remains available without JavaScript.
- Pending reads are cancelled and older query responses are ignored, including when a query changes during a vote. Search errors retain the previous results and recover on the next successful search. Vote confirmations are preserved.
- Search updates anchor the viewport to the search bar and retain its input/caret, sidebar scroll and unfinished proposal. The focus border/shadow surrounds the complete search bar instead of outlining the inner input. Results are announced through a hidden live status.
- Website integration suite: 17 tests / 254 assertions. Chrome suite: 9 tests / 177 assertions, covering debounce/coalescing, Polish text, no results, clearing, keyboard/button submission, stale responses, network recovery, concurrent voting, focus/caret, desktop/mobile layout and the existing voting/live-board flows. RuboCop passes; Brakeman reports no warnings. No database migration is required.

## Production community trial — 5 November 2026

- Production uses `bingo.xenor.ovh` on the separate production host/database, independent database/session secrets, public HTTPS and the existing participant/admin permissions. Staging keeps its HTTP authentication.
- The existing Discord app is shared. Its production interactions endpoint handles the community server locally and relays only verified commands from the configured private test server to staging. Signed bytes are preserved, staging verifies again, and the relay is bounded to two seconds and ephemeral replies. A server-only global `/bingo` command can be registered before the community invite; installation is still required for new community sign-ins.
- Explicit, idempotent trial setup prepares `/e/proba-glosowania` with 30 sample proposals and zero sample votes, open for seven days, and `/e/plansza-testowa` with a saved 25-cell live demo draw. Existing votes, dates and marks survive reruns. Production database seeds remain empty on ordinary deployments.
- Added production deployment/access checks and a daily private PostgreSQL backup script with locking, validated output and 14-day retention. Manual off-host snapshots continue to use `bin/backup-db production`.
- Application suite: 64 tests / 629 assertions. Chrome suite: 9 tests / 177 assertions. Added coverage for trial setup/reruns, preserving community activity, relay signatures/routing, primary database isolation, private responses, unsafe endpoints, upstream failures and the response deadline. RuboCop passes; Brakeman reports no warnings.

## Returning Discord members — 5 November 2026

- Reproduced a second-login failure: the participant uniqueness validator rejected the insert before `create_or_find_by!` could resolve the existing account. Account uniqueness remains enforced by PostgreSQL; removing the redundant validator lets Rails return the existing account and safely resolve simultaneous sign-ins.
- Added signed-interaction regressions for returning members, new links on repeated commands, retained votes/account identity, updated display names and simultaneous first sign-ins. Application suite: 66 tests / 657 assertions; RuboCop passes. No database migration is required.
- Confirmed installation in both Discord servers and registered `/bingo` directly in the production server, alongside its existing global command. The configured community trial thread was archived when checked; it must be reopened to use commands there.

## Search review and staging spelling — 5 November 2026

- Timed-out searches show the existing local error, release the busy status and retry on the normal poll, including when the query has not changed. Superseded searches, voting interruptions and navigation still discard intentional cancellations.
- Background polling continues while the search field has focus, preserving the query, caret, proposal draft and viewport. Other text fields still pause background refreshes.
- Added horizontal input padding and a matching autofill background/text color; the focus border remains around the entire search bar. Proposal and empty-result headings now use level two beneath the event title. Removed the unused `option_count` response and its extra count query.
- Staging uses `bingo.testing.xenor.ovh`, with HTTP authentication and the previous `bing.testing.xenor.ovh` / `uv-bingo.testing.xenor.ovh` aliases. Production remains `bingo.xenor.ovh`; its private-server Discord relay uses the corrected staging address.
- Application suite: 66 tests / 658 assertions. Chrome suite: 12 tests / 216 assertions. New checks exercise the actual eight-second abort, recovery through the normal fifteen-second poll with focus retained, another participant's vote while search stays focused, and Chrome's forced autofill state. RuboCop passes; Brakeman reports no warnings.

## Discord command deduplication — 5 November 2026

- The temporary global `/bingo` registration and the direct community-server registration both appeared in Discord. Removed only global command `1567947561598455909`, preserving the verified staging and production server commands. Discord's API confirms no global `/bingo` and exactly one server-specific `/bingo` in each server.
- Updated setup instructions to use server-specific registration after installation. This is a Discord configuration change; the application image and participant/voting data are unchanged.

## Daily backups and registration guard — 5 November 2026

- Production backups now follow the other apps' layout: `/home/ubuntu/backups/uv-bingo/prod_dump_*.sql.gz`, daily at 04:30 UTC, with seven-day retention. Installed the script at `/home/ubuntu/uv-bingo/db_backup_production.sh`; the installer replaces only Bingo's cron entry after verifying a backup. Reinstallation leaves exactly one Bingo job and all unrelated cron entries unchanged. Older custom-format dumps are retained.
- Added **Bingo-daily** to srv01's existing Unraid **rsync_daily** user script, pulling into `/mnt/user/Backups/Bingo/` without deletion. Existing jobs and the 03:00 local schedule are unchanged. Saved the previous script before the edit and ran only the new Bingo pull for verification.
- Production and srv01 dump hashes match. Restored the srv01 copy into a separate local PostgreSQL 17 database: 2 events, 55 proposals, 25 votes, 1 draw and 25 cells. Verified the snapshot digest, reproducible draw and board cell order, then removed the temporary database and local verification dump.
- Backup failure probes cover failed dumps, invalid SQL, lock failures, temporary-file cleanup, private permissions and retention only after successful validation. Shell syntax checks and the registration script's RuboCop check pass.
- The production deploy wrapper is unchanged and does not take a backup. Scheduled backups and optional manual snapshots are independent of deployments.
- Both the Discord registration wrapper and Ruby script reject `global` before credentials are loaded or an API request is made. No Discord registration or application redeployment was needed for these operational changes.

## Mobile header and event introduction — 5 November 2026

- On phones, navigation and account actions use a compact native disclosure menu. The event picker also collapses, retaining the current-event indicator and links to every event when opened. Desktop navigation and event links stay visible.
- The mobile hero displays the community artwork as a separate banner above the title and description. Text and the voting shortcut no longer overlap the image. The header, introductory spacing and voting-status panel are more compact, with touch targets of at least 44px for the menu and primary actions.
- Chrome checks at 320, 360, 390, 430 and 760px confirm no page overflow, no overlap between hero artwork and text, usable menu/event controls and correct admin/member/guest navigation. Checked event switching, admin navigation, logout, guest sign-in and the desktop layout.
- Existing website checks: 17 tests / 255 assertions. Existing voting and live-board browser journeys: 2 tests / 45 assertions. Tailwind build and diff checks pass. No database migration is required.

## Social link previews — 5 November 2026

- Added server-rendered Open Graph and X large-image card tags: title, description, canonical URL, site name, Polish locale, and the existing community artwork with its MIME type, dimensions and alternative text. Event descriptions also populate the regular description tag. Explicit UTF-8 metadata preserves Polish characters.
- Preview URLs use the configured site origin and omit query parameters. Home links retain the root URL; presentation/reveal links share their event's canonical URL. Login and admin pages use generic site metadata, without account details or login tokens.
- Verified homepage, event, presentation, reveal and private-page metadata locally, including quotes/ampersands, markup escaping, blank/long descriptions and staging/production origins. Existing website suite: 17 tests / 255 assertions. RuboCop and diff checks pass. No migration is required.
