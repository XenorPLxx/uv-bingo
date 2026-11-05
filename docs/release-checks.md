# First staging release — 5 November 2026

Staging: https://uv-bingo.testing.xenor.ovh

Verified:

- Application suite: 25 tests / 128 assertions covering votes, concurrent requests, draw reproducibility, login tokens, Discord signatures, permissions, and staging access rules.
- Chrome system tests: 2 tests / 17 assertions, including five final votes, mobile overflow, and a live update to a second browser.
- Rails eager loading and RuboCop pass. Brakeman reports no warnings. Ruby dependency and importmap audits report no known vulnerabilities.
- Pages, assets and `/cable` reject requests without staging Basic Auth. The minimal health check remains available. Unsigned webhook requests are rejected.
- Discord validated the public interaction endpoint. The user confirmed successful `/bingo` sign-in from the configured test channel.
- A separate live verification board accepted 50 simultaneous WebSocket subscriptions in approximately 4.9 seconds. All 50 received a committed board update through Solid Cable/PostgreSQL.
- A staging backup restored successfully into an isolated local PostgreSQL 17 database: one event, 30 options, 30 votes in that snapshot. The temporary restore database was removed afterward.

Rehearsal voting event: `/e/tga-2026-proba`.
Live verification board: `/e/kontrola-wdrozenia`.

These are clearly labeled test events. Production has configuration only and has not been deployed. Source is a separate local Git repository; no remote source repository was created.
