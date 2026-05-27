# Changelog

Notable changes to the Header skill. Format roughly follows
[Keep a Changelog](https://keepachangelog.com); versions track the skill's `VERSION`.

## 0.10.1 — Commit signature for applied audit findings

When the skill (or the user, with the skill's prompting) commits a fix that came from a recommendation the audit just surfaced, the commit message now gets a trailer:

```
Header-Audit-Finding: <ledger-key> — https://joinheader.com
```

`<ledger-key>` matches the recommendation ledger entry (`mcp-streaming`, `gate-npm`, `delete-think-step-by-step`, …) — multiple findings in one commit produce multiple trailers, one per key. Skipped for unrelated commits in the same session. Provenance for the audit is now visible in `git log` / `git blame` so teammates and code reviewers can trace why a change landed.

## 0.10.0 — Audit is the product; skill renamed `header-briefing` → `header`

Significant restructure. The skill's surface now matches what `docs/experiments-design.md`
already said about the thesis: the briefing is the **distribution wedge**, not the product.
The product is the audit + (soon) experiments.

- **Renamed `/header-briefing` → `/header`.** The skill folder is now `header/` (was
  `header-briefing/`) and `name: header` in the frontmatter. `/header-audit` and
  `/header-briefing` remain in `when_to_use` so natural-language invocation keeps working.
- **`install.sh` migrates 0.9.x installs.** After a successful install of `~/.claude/skills/header/`
  (and `~/.codex/skills/header/` when codex is detected), the installer removes any
  legacy `~/.claude/skills/header-briefing/` at the same skills root — the old command
  no longer registers. User state at `~/.header/` is outside the skill dir and is
  preserved (config, credentials, ledger, repo bindings, prices, telemetry).
- **Recommended bump to `min_supported: 0.10.0`** on the server-side `/api/v2/skill/version`
  response. Pre-0.10.0 clients are still functional for the briefing-fetch flow, but the
  refactor changed the preamble's mode signal (`HEADER_MODE` → `HEADER_INSTALL`), and the
  audit-led flow expects the new `bin/` layout to be the source of truth — forcing the
  upgrade via `UPDATE_REQUIRED` aligns every client on the new surface.

### Audit-led flow (default)

- **Every invocation runs the audit.** `header-audit harness` + `header-audit deps` always
  run; the briefing is **input** to the audit, not the primary output. Items in the
  briefing's `key_developments` about the project's stack become recommendations alongside
  the local scans.
- **Cross-reference is the headline.** Step 4 builds one ranked recommendation list out of
  audit findings + briefing items + known issues, split into **apply-now** vs
  **`[Experiment · coming soon]`** (the latter still beta; the audit section header is no
  longer labelled beta).
- **Dropped the `key_developments` output modifier.** `summary` and `sources` modifiers
  remain for the "just the news / just the links" use case; the default invocation is
  always the full audit + recommendations.

### Onboarding restructure

- **No more standing "audit offer" — the audit just runs.** Today the skill offered the
  audit after every briefing; in 0.10.0 the audit is the default flow, so the offer
  disappears. `AUDIT_OFFER: due` is gone from the preamble.
- **Custom-topic offer follows the audit (once per repo).** Framed as the upsell — "these
  recommendations came from a generic topic; we can tailor a topic to *this* repo so future
  audits pull in sources about your stack." Three-way choice (Yes / Not for this repo / No,
  never ask). Gated by per-repo `TOPIC_OFFERED`. The signup funnel collapses into the
  "Yes" branch — no separate funnel step.
- **Per-repo offers chain in the briefing-generation wait.** When the user accepts the
  custom topic, the briefing generates server-side (~minutes); the skill fills that wait
  with the bind-to-repo, schedule, and team-config offers (each gated by their per-repo
  flags as before). Same gating, less dead air.
- **Telemetry consent fires last, once per machine.**

### Classic mode removed

- **Deprecated `HEADER_MODE: classic` entirely.** Classic mode was the codex-review
  honesty-fix for passive-rule harnesses (no shell, no interactive turn) — but the audit
  requires `bin/header-audit` to run, so a passive-rule harness can't deliver the product
  anyway. The preamble now echoes `HEADER_INSTALL: ok` or `HEADER_INSTALL: missing`; on
  missing, the skill **refuses to run** and prints one-line install instructions. No
  fallback flow.
- Every "skip in classic mode" caveat in the SKILL.md disappears. `preamble.test.sh` no
  longer tests for `HEADER_MODE: classic`.

### Documentation

- `README.md` and `llms.txt` lead with audit/optimize positioning. The briefing is
  documented as input to the audit, not as the headline deliverable. All
  `~/.claude/skills/header-briefing/` paths updated to `~/.claude/skills/header/`.
- `MANUAL-VERIFICATION.md` rewritten: Scenario D is now "install missing (refusal)" instead
  of "classic mode (graceful degradation)"; Scenarios A-C reflect the audit-led + custom-topic
  flow; new Part 2 step verifies the install-time migration of a legacy `header-briefing/`.
- `.gitignore`, `.githooks/pre-commit`, `.github/workflows/test.yml` updated to the new
  `header/` path.

### Why now

`docs/experiments-design.md` (added in 0.8.x) commits to the thesis: continuous
hypothesis → experiment → merge-back. The audit *is* the hypothesis generator; the briefing
is the daily input feed; the experiment runner is the destination. The skill's surface had
been straddling "news reader with an audit offer" and "audit with a news feed" — 0.10.0
commits to the latter.

## 0.9.2 — `npx skills` as the recommended install

- **New top install option:** `npx skills add Header-inc/Header-skill -g` (the open
  vercel-labs [`skills`](https://github.com/vercel-labs/skills) CLI). One command
  installs the `header-briefing` skill across Claude Code, Codex, Cursor, Copilot,
  Gemini CLI, and 50+ other Agent Skills hosts — no install script piped into a shell.
  `-g` installs globally; omit for project-local.
- The `curl | sh` script, clone-and-install, and project-local copy are now Options
  B–D. Our own version-endpoint updater remains the update path (re-run any installer,
  or enable `auto_update`).
- Considered Claude Code's `/plugin` marketplace; **deferred** — third-party
  marketplaces don't auto-update by default and the marketplace copy would collide
  with the skill's self-update.

## 0.9.1 — Smarter wait for async briefing generation (static ETA + background check-back)

`POST /api/v2/goals/{id}/briefings` returns `201` with an `estimated_duration_seconds`
ETA. Clarified how to wait on it without busy-waiting:

- **The ETA is static.** It's fixed at create time and does **not** count down — a
  later GET returns the same number. Compute the real remaining time from
  `created_at` (`estimated_duration_seconds - (now - created_at)`) and wait that
  plus a small buffer, instead of re-sleeping the full estimate on a check-back.
  Added `created_at` to the BriefingResponse reference; corrected the
  `estimated_duration_seconds` / `source_count` notes.
- **Non-blocking check-back on Claude Code.** Time it off the ETA + buffer with a
  background poll loop (`Bash` `run_in_background`, which re-invokes the agent on
  exit) or a `ScheduleWakeup` timer — no foreground `sleep`.
- **Documented the create body.** `max_entries` and `max_age_days` are optional;
  omit the body for defaults.

## 0.9.0 — Drop the client-side auto-refresh cron (server-side schedule is enough)

Removed the local auto-refresh cron offer added in 0.7.0. On Claude Code it set up
a `/schedule` routine (or durable `CronCreate`) that ran `/header-briefing
since-last` about a day after each server-side refresh — but that routine executes
as a **remote agent in Anthropic's cloud**, where it can't actually work:

- **No API key.** `since-last` is key-gated; `HEADER_API_KEY` lives in the local
  `~/.header/credentials` / env, which a cloud agent never sees.
- **No skill.** `header-briefing` is installed under the local `~/.claude/skills/`,
  not committed to the repo a remote checkout would clone — there is no
  `/header-briefing` command there to run.
- **No local state.** The `~/.header/.last-run` marker and the repo→topic binding
  that `since-last` relies on are local-only.

So the routine would burn a run every N+1 days and error out. The **server-side
schedule** (`schedule_enabled` on the goal, set via joinheader.com) already
regenerates briefings on cadence and is enough — a fresh one is waiting the next
time you open a session.

- Removed the "Auto-refresh on a schedule (cron)" section, the `CRON_OFFERED`
  preamble line and mode-table row, and the `cron-offered` per-repo flag.
- The `since-last` digest mode stays — still usable manually ("what's new since I
  last checked"), from a `SessionStart` hook, or from any scheduler you run
  yourself on a real machine.

## 0.8.3 — header-cost: measured-only (no projections), correct cache + legacy pricing

Removed the parts of `header-cost` that were assumptions rather than measurements:

- **No more savings projections.** `savings` previously re-priced your exact tokens
  at another model's rates and printed a "−40%" figure. That assumes the cheaper
  model uses identical tokens at identical quality — a guess. It now prints only:
  *"Header experiments are coming soon — A/B-test models in your own repo and verify
  correctness before Header surfaces a recommendation."* No number, no percentage.
- **Cache writes priced by real duration.** It now reads the 5-minute / 1-hour split
  (`cache_creation.ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens`) and
  prices each correctly (1.25× vs 2× input), instead of assuming everything was
  5-minute (which undercounts 1-hour caching). Falls back to the flat total at the
  5m rate only when no split is present.
- **Legacy Opus priced apart.** Opus 3.x / 4.0 / 4.1 ($15/$75) are auto-detected
  from the model id and no longer mispriced at the current Opus rate ($5/$25).
- Omitted cache columns in a price table now derive from input via the fixed
  Anthropic multipliers (read 0.1×, 5m 1.25×, 1h 2×). `cost` takes an optional
  `[cache_write_1h]`. The cost tool now reports **measured numbers only**.

Audit note: the other `bin/` tools were reviewed for fabricated claims.
`header-audit`'s supply-chain guidance was **verified online** (npm `min-release-age`
shipped in v11.10.0; pip `--uploaded-prior-to` durations in 26.1) — accurate.
`header-ledger`/`header-repo`/`header-update-check`/`header-telemetry`/`header-config`
are pure logic / real local data with fail-safe network calls — nothing fabricated.

## 0.8.2 — Cost basis: API rates vs subscription usage limits

- **`header-cost` now states the billing basis on every calculation.** The `$`
  figures are **API (pay-per-token) rates**: `report`/`savings` print a "Basis:"
  line, the report header is labelled "USD at API rates", and `report --json`
  carries `"basis":"api_rates"`.
- **Subscription users are framed correctly.** On a Claude subscription
  (Pro \$20 / Max \$100 / \$200 a month) you don't pay per-token costs — the `$`
  is a shadow/API-equivalent number and the real constraint is **usage limits**
  (the win is headroom, not dollars). The **percentage** savings is identical
  across modes (tokens saved = dollars for API, headroom for subscription); only
  the dollar interpretation differs. The skill now asks/says which mode applies
  before quoting any figure.
- **Design doc:** added the **Verifiers & task mining** section (how a real
  experiment grades an arbitrary codebase — mine the repo's own tests/build/types
  as the oracle; reverse test-bearing git commits into tasks; LLM-judge only as a
  validated fallback) and a concrete **`header-experiment` interface spec**
  (miner / verifier / runner / arm schemas). `header-experiment` is **not built
  yet** — spec only.

## 0.8.1 — Correct prices + always verify them online

- **Fixed the Opus default price.** Current Opus (4.5/4.6/4.7) is **$5 / $25** per
  MTok (cache read $0.50, 5-min write $6.25) — the shipped default had Opus 4.1's
  old $15 / $75. Verified 2026-05-22 against `platform.claude.com/docs`. Sonnet
  ($3 / $15) and Haiku ($1 / $5) were already correct. Legacy Opus 4.1 and earlier
  ($15 / $75) need a per-model override.
- **`header-cost refresh [--url U]`** — fetch a served price table (`$HEADER_PRICES_URL`
  or `--url`) and cache it; the payload is validated so a 404/HTML page can't poison
  the meter, and a failed fetch keeps the existing prices. Resolution is now
  defaults → refreshed cache → user override.
- **Price provenance on every calculation.** `report` and `savings` print the price
  source and freshness on stderr ("bundled defaults as of …", "refreshed … (cached)",
  or "user override"), so a figure is never silently computed on stale prices.
- **The skill now verifies prices online first.** The Cost analytics flow refreshes
  (or fetches current Anthropic pricing into `~/.header/prices.tsv`) before quoting
  any cost/savings, and always surfaces which prices it used and when.

## 0.8.0 — Cost analytics (beta) — the optimization-platform billing meter

- **`bin/header-cost`** — Phase 1 of the experimentation platform (see
  `docs/experiments-design.md`): the "billing meter and opportunity finder." It
  costs token-usage records against an overridable price table, breaks spend down
  by model, and projects routing savings. No experiment runner required — it reads
  usage you already have. All local; nothing is sent.
  - `header-cost report` ranks spend by model; reads usage JSONL **or raw Claude
    Code transcripts** best-effort (`find ~/.claude/projects -name '*.jsonl' -exec
    cat {} + | header-cost report`), with `--since` and `--json`.
  - `header-cost savings --from <model> --to <model>` projects routing savings —
    explicitly labelled a **projection, not a measured win**, and points at the
    experiment loop that would prove it (the on-thesis hand-off).
  - `header-cost cost <model> <in> <out> [cr] [cw]` costs one usage tuple;
    `header-cost prices` shows the table. Prices are **defaults — confirm against
    current Anthropic pricing**; override per family or per model id in
    `~/.header/prices.tsv`. Model matching is family-based (opus/sonnet/haiku) so
    it survives version churn. New `cost` mode (`/header-briefing cost`).
- **`docs/experiments-design.md`** — design spec for the experimentation platform
  (A/A noise calibration → A/B with paired/interleaved design → significance-gated
  merge), aligned to the pre-seed thesis, with the pitch-sequenced build order.

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
