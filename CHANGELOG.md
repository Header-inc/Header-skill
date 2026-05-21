# Changelog

Notable changes to the Header briefing skill. Format roughly follows
[Keep a Changelog](https://keepachangelog.com); versions track the skill's `VERSION`.

## 0.4.0 — Per-repo topic memory

- **Repo → topic memory** (`bin/header-repo`): when you create a custom topic
  while working in a repo, the skill offers to remember it for that repo. New
  sessions there resolve the bound topic automatically (Step 0, above the global
  default) instead of falling back to the public topic. Stored in a local global
  registry (`~/.header/repos.jsonl`) keyed by git remote (path fallback) — never
  written inside the repo, never sent. New `repo_memory` config key (default true).
- **Session-start freshness:** in a bound repo with a key, the skill fetches the
  topic's latest briefing and surfaces it when it's newer than what you last saw
  (per-repo `seen` marker).
- **Scheduled briefings:** offers to put the repo's goal on a 3 / 7 / 14 / 30-day
  schedule via `PUT /api/v2/goals/{id}` (`schedule_enabled`,
  `schedule_frequency_days`). Header regenerates briefings server-side on that
  cadence — they're waiting next time you open a session.

## 0.3.2 — Telemetry client hardening

- Each telemetry event carries an `event_id` (idempotency key for safe
  server-side dedup under at-least-once retries).
- Sync batches are capped at 100 events per request; the cursor advances by
  the number actually sent.
- On the `full` tier, sends are authenticated with the API key when one is
  present (ties usage to the account); `anonymous` never attaches a key.

## 0.3.1 — Source API wiring

- `add-source` and the custom-sources prompt now use the real source API:
  preview (`POST /sources/preview`) → create (`POST /sources/`) → attach via
  `POST /source-groups/{id}/members`. Topics link by `source_group_ids` (not
  `source_ids`).
- Auto-create can build a tailored source group via `sources/recommend` →
  `/recommend/commit`.

## 0.3.0 — Close the loop

- **Recommendation ledger** (`bin/header-ledger`): local, append-only record of
  applied / dismissed / snoozed recommendations. The briefing skips dismissed
  items and follows up on applied ones. Local-only; `ledger` config key.
- **Source provenance:** each recommendation links the source article behind it.
- **Diff-aware relevance:** the audit weights recommendations toward recently
  changed code (recent git activity).
- **Telemetry** (opt-in, consent-gated; `bin/header-telemetry`): off / anonymous /
  full tiers. Usage metadata only — workspace content, repo and branch names are
  never sent. `telemetry` config key.
- **Goal auto-tuning** (opt-in): feed the ledger back into the topic goal via
  `PUT /goals` so future briefings sharpen. `auto_tune` config key.
- **New modes:** auto-create a topic from the project audit, `add-source <url>`,
  and a since-last digest (`dashboard?since=`) with automatic `.last-run` tracking.

## 0.2.0 — Auto-update

- Backend-driven update checks: the preamble runs `bin/header-update-check`, which
  queries `GET /api/v2/skill/version` and surfaces `UPDATE_AVAILABLE` / `UPDATE_REQUIRED`.
- `UPDATE_REQUIRED` (installed version below the API's `min_supported`) is non-optional;
  everything else is an opt-in prompt — Yes / Always / Not now / Never — with an
  escalating snooze (24h → 48h → 1 week).
- New config keys: `auto_update` (default false), `update_check` (default true).
- `install.sh` now installs/updates atomically (stage + swap) and rolls back on failure.
- Fail-safe: when the version endpoint is unreachable or not yet deployed, the check
  reports "up to date" and never errors — the skill ships dormant until the endpoint is live.

## 0.1.0 — Enterprise foundation & onboarding

- `bin/header-config`: persisted config at `~/.header/config` (get/set/list/defaults).
- `## Preamble`: classic vs enterprise resolution, non-interactive guard, state echo.
- First-run onboarding: welcome, language prompt, post-briefing signup funnel,
  save-the-key flow to `~/.header/credentials`.
- `install.sh`: one-command installer (Claude Code + Codex).
- Plain-bash test suite; `VERSION` stamped and mirrored in the SKILL.md frontmatter.
