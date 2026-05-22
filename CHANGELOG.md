# Changelog

Notable changes to the Header briefing skill. Format roughly follows
[Keep a Changelog](https://keepachangelog.com); versions track the skill's `VERSION`.

## 0.7.0 — Team config layer + auto-refresh cron

- **Committed team config (`<repo>/.header/config`).** A repo can now ship a
  shared Header policy layer that teammates inherit on clone with zero setup.
  New `header-config` subcommands — `team-init`, `team-set`, `team-get`,
  `team-path`, `team-show` — read/write a flat `key: value` file at the repo
  root. The preamble echoes `TEAM_CONFIG` and `TEAM_TOPIC`; Step 0 slots the
  team topic **above** the personal/global default but **below** an explicit
  personal `header-repo` binding and any env var, so a fresh clone inherits the
  team topic while any developer can still override locally. Precedence overall:
  **env › team `.header/config` › personal `~/.header/config` › built-in
  default** (applied to `default_topic`, `staleness_days`, `language`).
  - **Security:** the committed file is **read as data only** (grep/sed, never
    sourced), and only an allow-list of team-shareable keys is honored —
    `default_topic`, `staleness_days`, `schedule_frequency_days`, `language`.
    Consent/code-execution keys (`telemetry`, `auto_update`, `auto_tune`,
    `update_check`) are **ignored** in a committed file and surfaced by
    `team-show`, so a pushed change can't flip a teammate's privacy or run code.
  - The skill **offers to write + commit `.header/config`** right after a topic
    is created/bound (recommended for shared repos; optional when solo), gated by
    a per-repo `team-config-offered` flag.
- **Auto-refresh on a schedule (cron).** When a server-side schedule (every N
  days) is enabled for a repo's topic, the skill now offers to set up a
  persistent local job (`/schedule` routine / durable `CronCreate` on Claude
  Code; a documented one-liner elsewhere) that runs `/header-briefing
  since-last` at **N+1 days** — the +1 guarantees the server briefing exists
  before the pull, and the `?since=` guard makes an early/duplicate run a no-op.
  `since-last` is now a first-class mode; the offer is gated by a per-repo
  `cron-offered` flag.

## 0.6.0 — Recurring audit offer, reliable post-briefing offers, richer triggers

- **The audit offer is now recurring, not one-time.** It's made after **every**
  interactive briefing (like re-running a linter), instead of once behind a
  `.audit-offered` marker. The marker is gone — a codebase shifts between runs,
  so a fresh harness/deps scan is useful each time. (Within a single session the
  skill won't re-ask if it already offered.)
- **Post-briefing offers are surfaced in the preamble.** It now echoes
  `AUDIT_OFFER` (always `due` interactively), `TOPIC_OFFERED`, `SCHEDULE_OFFERED`,
  and `AUTOTUNE_OFFERED` alongside the existing `WELCOME_SEEN` /
  `TELEMETRY_PROMPTED` flags. These offers were being silently skipped because
  they relied on inline marker checks buried at the tail of a long flow with no
  up-front reminder; the enterprise table documents each new line.
- **Topic and schedule offers are now per-repo, not per-machine.** Both are
  inherently bound to a repository (each repo can get its own tailored topic and
  refresh cadence), but the old global `.topic-offered` / `.schedule-offered`
  markers meant offering once in *any* repo suppressed the offer everywhere else.
  They're now tracked via a new `header-repo flag <name> [set]` mechanism keyed
  by git remote (stored in `~/.header/repo-flags/`), so every repo gets the
  offer exactly once. `AUTOTUNE_OFFERED` stays global — it flips the machine-wide
  `auto_tune` config key.
- **Expanded skill triggers.** `when_to_use` and `description` now list
  audit/optimization triggers (audit, dependency upgrade, migration, optimize
  codebase, reduce token cost, supply-chain, CLAUDE.md/prompt debt) alongside
  the briefing triggers (briefing, best practices, latest best practices,
  what's new in agents/MCP/coding tools).

## 0.5.2 — Audit: bash tool security posture

- `header-audit harness` now classifies the agent's **Bash-tool permission
  posture** from Claude Code settings: `bypass` (no gating), `denylist`
  (blacklist — bypassable), or `allowlist` (whitelist-leaning), with the
  matching `allow`/`deny` entries. The audit recommends moving toward a command
  allow-list where the agent can reach production, per the briefing insight that
  blacklists are bypassable. No new dependencies — pure awk/grep.

## 0.5.1 — Fix SKILL.md frontmatter YAML

- Quote the `description` and `when_to_use` frontmatter values. They contained
  `: ` (colon-space), which strict YAML parsers (e.g. Codex) reject as an
  invalid nested mapping — Codex skipped loading the skill entirely ("mapping
  values are not allowed in this context"). Claude Code's lenient parser had
  masked this. A new test guards the whole frontmatter block against unquoted
  colon-space values (and parses it with a real YAML loader when available).

## 0.5.0 — Audit mode (beta)

- **`audit` mode** (`bin/header-audit`) — a local, no-account scan of the agent
  *harness*, surfaced proactively in onboarding (not just on request):
  - **Prompt/config debt:** locates `CLAUDE.md`, `AGENTS.md`, settings, commands,
    subagents, MCP config; reports per-file size + token estimate; flags known
    cargo-cult prompt patterns (think-step-by-step, role puffery, "don't
    hallucinate", JSON-format nagging, …) so they can be pruned.
  - **Dependency & supply-chain:** detects ecosystems and tool versions, and
    whether an install-cooldown gate is in place; recommends a
    `min-release-age` / `--uploaded-prior-to` cooldown (npm ≥ 11.10, pip ≥ 26.1,
    locally and in CI) to block freshly-compromised packages.
- **Recommendation → hypothesis → experiment:** findings split into apply-now
  (deletions, gates, patches) and `[Experiment · coming soon]` (model/major
  upgrades). Experiments aren't supported yet; the skill captures **demand**
  instead — a new `wanted` ledger action records which experiments users want,
  and (consent-gated) telemetry aggregates the counts.
- Onboarding now plants the optimization vision and offers the audit once after
  the first briefing (`.audit-offered` marker).

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
