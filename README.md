# Header Briefing Skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A skill for agentic coding tools that fetches intelligence briefings from [Header](https://joinheader.com) and surfaces recommendations relevant to your current project. Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but works in any agent with shell access (Cursor, Aider, OpenAI Codex CLI, Goose, and others) — the skill is plain `bash` and `curl`, with no build step and no runtime dependencies.

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources covering AI agent frameworks, MCP, coding tools, and related topics.

## Installation

The skill is a small folder — `header-briefing/` (`SKILL.md` + `bin/` + `VERSION`) — installed into your agent's skills directory.

### Option A: `npx skills` (recommended)

One command, and it works in Claude Code, Codex, Cursor, Copilot, Gemini CLI, and [50+ other Agent Skills hosts](https://github.com/vercel-labs/skills) — via the open [`skills`](https://github.com/vercel-labs/skills) CLI, with no install script piped into a shell. Needs Node (for `npx`).

```bash
npx skills add Header-inc/Header-skill -g
```

`-g` installs globally for your user (available across all projects) — drop it to scope to the current project. The CLI finds the `header-briefing` skill in this repo and installs just that folder; inside an agent session it installs non-interactively. Add `-a <agent>` to target specific hosts, `--list` to preview, and re-run to update.

### Option B: One-command install script

```bash
curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
```

Installs into `~/.claude/skills/header-briefing/` (and `~/.codex/skills/` if Codex is detected). No Node required — just `sh`, plus `git` or `curl`. Re-run any time to update.

### Option C: Clone and install

```bash
git clone https://github.com/Header-inc/Header-skill.git
cd Header-skill && ./install.sh
```

To update later: `cd Header-skill && git pull && ./install.sh`.

### Option D: Project-local (available only in one project)

```bash
git clone https://github.com/Header-inc/Header-skill.git
mkdir -p .claude/skills
cp -R Header-skill/header-briefing .claude/skills/header-briefing
```

Start a new Claude Code session (or restart your current one) to pick up the skill.

> **Note:** If you install both globally and in a project, the global version takes precedence and the project-local copy is silently ignored. Pick one method per skill name.

### Using with other harnesses (Cursor, Aider, Codex CLI, etc.)

Most hosts are covered by **Option A** — `npx skills add Header-inc/Header-skill -a <agent>` (e.g. `-a cursor`, `-a codex`). For anything the CLI doesn't cover, the skill is a folder of plain `bash` + `curl` — no build step, no runtime dependencies — so install the `header-briefing/` folder where your agent looks for skills, or point your agent at `header-briefing/SKILL.md` directly:

- **Cursor**: add `header-briefing/SKILL.md` as a project rule.
- **Aider**: `aider --read header-briefing/SKILL.md` (or add to `CONVENTIONS.md`).
- **OpenAI Codex CLI**: `install.sh` installs into `~/.codex/skills/` automatically when `codex` is detected.
- **Goose / Cline / other**: reference the `SKILL.md` contents in your agent's instructions.

The frontmatter (`name`, `version`, `description`, `when_to_use`, `argument-hint`, `allowed-tools`) is Claude-Code-specific and is safely ignored by other harnesses. Body sections use a `**Claude Code only:**` callout for behaviors that depend on Claude Code features; other harnesses can read past those callouts safely.

**What works where.** The core briefing workflow runs in any agent with shell access. The enterprise features need more:

| Capability | Requirement |
|---|---|
| Public + authenticated briefings | Any agent with shell access (`bash` + `curl`) |
| Persisted config (`~/.header/config`) | The `bin/header-config` helper resolves — installed via `install.sh` or a folder copy |
| First-run welcome + signup onboarding | An interactive agent session (Claude Code, or an agentic Cursor / Aider / Codex session) |

If `bin/header-config` is not found, the skill runs in **classic mode** — the briefing workflow works exactly as before, with config and onboarding switched off. It prints a one-line notice so a partial install is visible rather than silent.

## Usage

### Default: Agentic Coding Briefing (No Auth Required)

Simply invoke the skill:

```
/header-briefing
```

This will:

1. Fetch the latest "Self Improving Agent" briefing from Header's public API
2. Read your project's config files (CLAUDE.md, README, package.json, etc.) to understand your tech stack
3. Compare the briefing's key developments against your project's patterns and dependencies
4. Present actionable recommendations with rationale
5. Offer to implement any recommendations you select

Your project data never leaves your machine — the workspace audit happens locally after the briefing is fetched.

### Audit your agent setup (beta)

```
/header-briefing audit
```

A local, no-account scan of your **agent harness** — surfaced proactively during onboarding, or on request. Two checks:

- **Prompt/config debt** — reads `CLAUDE.md`, `AGENTS.md`, Claude Code settings/commands/subagents, and MCP config; reports their size and per-turn token cost; flags stale "cargo-cult" prompt patterns (e.g. `think step by step`, role puffery, "don't hallucinate", JSON-format nagging) that newer models make redundant, so you can prune them. It also classifies your **Bash-tool permission posture** (allow-list / deny-list / bypass) and recommends a command allow-list where the agent can reach production.
- **Dependency & supply-chain** — detects your package ecosystems and recommends an install-cooldown gate (`min-release-age` for npm, `--uploaded-prior-to` for pip; needs npm ≥ 11.10 / pip ≥ 26.1, locally and in CI) that refuses packages published in the last N days — blocking freshly-compromised releases before they're caught and pulled.

Everything is read locally; nothing leaves your machine. Findings split into **apply-now** fixes (deletions, the supply-chain gate, security patches) and changes worth **proving with an experiment** — experiment execution is *coming soon* (not yet supported); for now the skill records which experiments you want so they're prioritized.

### Cost analytics (beta)

```
/header-briefing cost
```

The first piece of the optimization platform: a local "billing meter" that reports your **measured** token spend. It reads usage JSONL — or your raw Claude Code transcripts directly:

```bash
find ~/.claude/projects -name '*.jsonl' -exec cat {} + | header-cost report
```

`report` ranks spend by model — real token counts × verified prices, with cache writes priced by their real 5-minute/1-hour duration and legacy Opus (3.x/4.0/4.1) priced apart from current Opus. It does **not** guess what switching models would save: a price re-rating of the same tokens is a projection, not a measurement, so `header-cost savings` only points at the experiment loop (*"Header experiments are coming soon…"*) that would actually prove a switch. Prices drift, so the skill **verifies them before quoting figures** (`header-cost refresh` from a served `HEADER_PRICES_URL`, or a fetch of current Anthropic pricing into `~/.header/prices.tsv`), and `report` always prints which prices it used and how fresh. The bundled defaults are a dated floor (verified 2026-05-22: Opus 4.5+ $5/$25, Sonnet $3/$15, Haiku $1/$5). All local; nothing is sent.

**Billing basis:** the `$` figures are **API (pay-per-token) rates** (the tool says so). On a Claude subscription (Pro $20 / Max $100 / $200 a month) you don't pay these — the `$` is a shadow/API-equivalent number and your real constraint is **usage limits**, so spend reads as cap consumption rather than dollars off a bill.

### Browse Public Topics

You can also ask the skill to browse Header's public topic catalog instead of using the default topic. Public topics span a variety of technology areas and each has its own curated source list and briefing history.

Ask Claude to list available topics or fetch a briefing from a specific topic by name or ID.

### Custom Briefings (API Key Required)

For briefings tailored to your specific project and tech stack you need a free Header account. On its first run (after delivering a briefing) the skill offers a quick signup walkthrough; you can also set it up yourself:

1. Sign up at [joinheader.com](https://joinheader.com) — free trial, no credit card
2. Create an API key with **read + write** access from **Settings ▸ API Keys** (write is required to create custom topics)
3. Make the key available to the skill — either export it:

   ```bash
   export HEADER_API_KEY="hdr_sk_..."
   ```

   or let the onboarding funnel save it to `~/.header/credentials` (a file readable only by you).

With an API key, you can:

- **Create custom topics** with goal descriptions tailored to your project
- **Generate briefings on demand** for any of your topics
- **Update goals** to refine focus areas and keywords over time
- **Check briefing status** for async generation (`IN_PROGRESS`, `COMPLETED`, `FAILED`)

### Per-repo topic memory

When you create a custom topic while working in a repository, the skill offers to **remember it for that repo**. After that, running `/header-briefing` in the same repo automatically uses your topic instead of the public default — no argument needed. Bindings live in a local registry (`~/.header/repos.jsonl`) keyed by the repo's git remote (with a path fallback); nothing is written inside your repo and nothing is sent. New sessions also check whether a newer briefing has appeared and surface it. Disable with `header-config set repo_memory false`; forget one repo with `header-repo clear`.

You can also put a repo's topic on a **schedule** (every 3 / 7 / 14 / 30 days). Header then regenerates the briefing server-side on that cadence, so a fresh one is waiting the next time you open a session — even if you never trigger it manually.

The personal binding above stays on your machine. To share a topic with a **whole team**, commit a [`.header/config`](#team-config-headerconfig) — teammates inherit it on clone with no setup.

## Configuration

Configuration comes from four places, highest priority first: **environment variable › committed team config (`<repo>/.header/config`) › personal config (`~/.header/config`) › built-in default**. Environment variables always win; a committed team config lets a whole repo share settings (see [Team config](#team-config-headerconfig)).

### Environment variables

| Variable | Description |
|----------|-------------|
| `HEADER_API_KEY` | Header API key (`hdr_sk_...`) for authenticated workflows. Only needed for custom topics and on-demand briefing generation. |
| `HEADER_LANGUAGE` _(Beta)_ | Language for output rendering (e.g. `Turkish`, `Spanish`). Defaults to English. The agent translates the presentation; API content stays English. |
| `HEADER_DEFAULT_TOPIC` | Topic UUID used when no argument is passed. Defaults to the "Self Improving Agent" public topic. |
| `HEADER_STALENESS_DAYS` | Maximum briefing age (in days) before warning that content may be stale. Defaults to 7. |
| `HEADER_HOME` | Override the state directory. Defaults to `~/.header`. |
| `HEADER_NONINTERACTIVE` | Set to `1` for scheduled / unattended runs so onboarding prompts are suppressed (`CI=1` is treated the same way). |

### Persisted config (`~/.header/config`)

`bin/header-config` reads and writes a flat `key: value` file at `~/.header/config`, so a preference set once survives across sessions without re-exporting an environment variable. The skill's preamble calls it for you; to set a preference by hand, call the helper inside the installed skill folder:

```bash
~/.claude/skills/header-briefing/bin/header-config set language Turkish
~/.claude/skills/header-briefing/bin/header-config list
```

Recognized keys: `default_topic`, `language`, `staleness_days`, `auto_update`, `update_check`, `ledger`, `telemetry`, `auto_tune`, `repo_memory`. Run the helper with `defaults` to see every key and its default value.

### Team config (`.header/config`)

To share a topic (and a couple of settings) with a whole team, **commit a `.header/config` at the repo root**. Every teammate's skill reads it automatically on clone — no per-person setup — and it sits above each developer's personal `~/.header/config` but below their own env vars and explicit per-repo bindings. The skill offers to create and commit it for you right after you make a topic; it's recommended for shared repos and optional when you're solo.

Keep it to **team-relevant settings only**. Only an allow-list is honored: `default_topic`, `staleness_days`, `schedule_frequency_days`, `language`. Consent and update keys (`telemetry`, `auto_update`, `auto_tune`, `update_check`) are **ignored** from a committed file by design — they stay personal, so a pushed change can never flip a teammate's privacy or trigger code. The file is read as data only, never sourced.

```bash
~/.claude/skills/header-briefing/bin/header-config team-init <topic-uuid>   # scaffold ./.header/config
~/.claude/skills/header-briefing/bin/header-config team-set staleness_days 14
~/.claude/skills/header-briefing/bin/header-config team-show                 # honored vs ignored keys
git add .header/config && git commit -m "Add Header team config"
```

### State directory

The skill keeps a small amount of state under `~/.header/` (override with `HEADER_HOME`):

| File | Purpose |
|---|---|
| `config` | Persisted configuration (flat `key: value`). |
| `credentials` | Optional — your API key, saved by the onboarding funnel (`chmod 600`; read as data, never executed). |
| `.welcome-seen`, `.signup-state`, `.language-prompted`, `.telemetry-prompted`, `.autotune-offered` | Global onboarding markers, so machine-wide first-run prompts show exactly once. (The audit offer is intentionally **not** marker-gated — it's offered on every interactive run.) |
| `last-update-check`, `update-snoozed`, `version-info.json` | Update-check cache, snooze state, and the last version-endpoint response. |
| `ledger.jsonl` | Recommendation ledger (applied/dismissed/snoozed) — local-only, never sent. |
| `telemetry.jsonl` | Local usage events — only written if you opt into telemetry. |
| `repos.jsonl` | Repo → topic bindings (which custom topic each repository uses) — local-only, never sent. |
| `repo-seen/` | Per-repo "last briefing seen" markers, for the session-start freshness check. |
| `repo-flags/` | Per-repo onboarding flags (e.g. `topic-offered`, `schedule-offered`) so those offers fire once **per repo** — every repo can get its own tailored topic and schedule. |
| `prices.tsv` | Optional — token price overrides for `header-cost` (per family or per model id). Built-in defaults are used if absent. |
| `prices-cache.tsv` | Optional — price table fetched by `header-cost refresh` (validated). Sits between defaults and your override. |

## Updating

On each run the skill checks for a newer version against Header's version endpoint (cached; 5-second timeout; silent and harmless if the endpoint is unreachable). When a newer version is available it offers to update, and remembers your choice:

- **The prompt** offers Yes / Always / Not now / Never. "Always" sets `auto_update`; "Never" sets `update_check false`.
- **Auto-update:** `~/.claude/skills/header-briefing/bin/header-config set auto_update true` — future updates install silently.
- **Disable checks:** `~/.claude/skills/header-briefing/bin/header-config set update_check false`.
- **Update manually anytime** by re-running your installer — `npx skills add Header-inc/Header-skill -g` (Option A), or the script:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
  ```

If Header ships a breaking API change, the version endpoint marks a minimum supported version; a skill older than that says so rather than failing silently. Updates install atomically and roll back on failure.

## Telemetry

Telemetry is **off by default** and opt-in. The skill asks once during onboarding; change it any time:

```bash
~/.claude/skills/header-briefing/bin/header-config set telemetry off|anonymous|full
```

- **off** — nothing recorded or sent.
- **anonymous** — aggregate usage only, no identifier.
- **full** — usage plus a random install id (not derived from your identity); if an API key is set, full-tier sends are authenticated so usage ties to your account.

**Sent:** which path ran, outcome, duration, skill version, OS, and how many recommendations you surfaced/applied. **Never sent:** your code, file paths, repo or branch names, or briefing content — the recommendation ledger and the workspace audit stay on your machine. Sends are rate-limited, fail-safe, and stripped of local-only fields before they leave.

## Development

The skill is plain `bash` — the test suite has no dependencies:

```bash
cd header-briefing && ./test/run.sh
```

Enable the pre-commit hook once per clone so the suite runs — and blocks — on every commit:

```bash
git config core.hooksPath .githooks
```

## License

MIT — see [LICENSE](LICENSE) for details.
