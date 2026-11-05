# First staging release — 5 November 2026

Staging: https://uv-bingo.testing.xenor.ovh

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
