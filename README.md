# Header Skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A skill for agentic coding tools that **audits and optimizes** the AI coding agent's own setup — `CLAUDE.md`, model choice, dependencies, settings — and enriches the recommendations with the latest agentic-coding briefing from [Header](https://joinheader.com). Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but works in any agent with shell access (Cursor, Aider, OpenAI Codex CLI, Goose, and others) — the skill is plain `bash` and `curl`, with no build step and no runtime dependencies.

Every invocation runs the audit. The briefing is **input** to the audit: items in the briefing about your stack become recommendations alongside the local scans for prompt-config debt and supply-chain gaps. Public briefings work with no authentication; an API key unlocks custom topics tuned to your repo.

## Installation

The skill is a small folder — `header/` (`SKILL.md` + `bin/` + `VERSION`) — installed into your agent's skills directory.

### Option A: `npx skills` (recommended)

One command, and it works in Claude Code, Codex, Cursor, Copilot, Gemini CLI, and [50+ other Agent Skills hosts](https://github.com/vercel-labs/skills) — via the open [`skills`](https://github.com/vercel-labs/skills) CLI, with no install script piped into a shell. Needs Node (for `npx`).

```bash
npx skills add Header-inc/Header-skill -g
```

`-g` installs globally for your user (available across all projects) — drop it to scope to the current project. The CLI finds the `header` skill in this repo and installs just that folder; inside an agent session it installs non-interactively. Add `-a <agent>` to target specific hosts, `--list` to preview, and re-run to update.

### Option B: One-command install script

```bash
curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
```

Installs into `~/.claude/skills/header/` (and `~/.codex/skills/` if Codex is detected). No Node required — just `sh`, plus `git` or `curl`. Re-run any time to update.

The installer also **migrates a previous `header-briefing/` install** at the same skills root — it removes the legacy folder after a successful install so the old `/header-briefing` command no longer appears. State at `~/.header/` (your API key, config, ledger, repo bindings) is outside the skill dir and is preserved.

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
cp -R Header-skill/header .claude/skills/header
```

Start a new Claude Code session (or restart your current one) to pick up the skill.

> **Note:** If you install both globally and in a project, the global version takes precedence and the project-local copy is silently ignored. Pick one method per skill name.

### Using with other harnesses (Cursor, Aider, Codex CLI, etc.)

Most hosts are covered by **Option A** — `npx skills add Header-inc/Header-skill -a <agent>` (e.g. `-a cursor`, `-a codex`). For anything the CLI doesn't cover, the skill is a folder of plain `bash` + `curl` — no build step, no runtime dependencies — so install the `header/` folder where your agent looks for skills, or point your agent at `header/SKILL.md` directly:

- **Cursor**: add `header/SKILL.md` as a project rule.
- **Aider**: `aider --read header/SKILL.md` (or add to `CONVENTIONS.md`).
- **OpenAI Codex CLI**: see the dedicated notes just below.
- **Goose / Cline / other**: reference the `SKILL.md` contents in your agent's instructions.

#### OpenAI Codex CLI

The installable skill is the **`header/` subfolder**, not the repository root — there is no `SKILL.md` at the root, so a root-level install fails with `SKILL.md not found`. Point Codex at the subfolder:

- **Repo:** `Header-inc/Header-skill`  ·  **Skill path:** `header`  ·  **Installed location:** `$CODEX_HOME/skills/header` (default `~/.codex/skills/header`).
- `npx skills add Header-inc/Header-skill -a codex` (Option A) or `install.sh` (Option B, which installs into `~/.codex/skills/` automatically when `codex` is on `PATH`) both target the `header/` folder for you.
- **Restart Codex after installing or updating.** Codex loads skills at session startup, so a freshly installed `/header` won't appear until you start a new session.

Two Codex-specific rough edges the skill now handles itself:

- **Executable bits.** Some download paths copy `bin/*` without the executable bit, which would make the preamble report `HEADER_INSTALL: missing`. The preamble self-heals (`chmod +x` best-effort) and echoes `HEADER_SELFHEAL:` when it does. If the skill directory is read-only, repair it manually: `chmod +x ~/.codex/skills/header/bin/* ~/.codex/skills/header/test/run.sh`.
- **Filesystem sandbox.** Under `workspace-write`, Codex usually excludes `~/.header`, so the recommendation ledger, config, and run markers can't persist. The audit still runs; the preamble flags this with `HEADER_STATE: readonly`. To keep state, add `~/.header` to the sandbox's writable roots, or set `HEADER_HOME` to a writable path (e.g. `export HEADER_HOME="$PWD/.header"`).

Validate an installed copy without a full checkout: `~/.codex/skills/header/test/run.sh installed`.

The frontmatter (`name`, `version`, `description`, `when_to_use`, `argument-hint`, `allowed-tools`) is Claude-Code-specific and is safely ignored by other harnesses. Body sections use a `**Claude Code only:**` callout for behaviors that depend on Claude Code features; other harnesses can read past those callouts safely.

The skill requires its `bin/` helpers to be resolvable. If the preamble echoes `HEADER_INSTALL: missing` the skill refuses to run and points the user at the installer — there's no degraded fallback flow, since the audit itself depends on `bin/header-audit`.

## Usage

### Default: audit + briefing-enriched recommendations (no auth required)

Invoke the skill:

```
/header
```

(`/header-audit` is an equivalent natural-language trigger; `/header-briefing` is the legacy command name kept working for compatibility.)

Every invocation:

1. **Runs the audit** locally — `header-audit harness` (prompt-config debt, `CLAUDE.md`/`AGENTS.md` size, model declaration, cargo-cult patterns, Bash-tool permission posture), `header-audit deps` (ecosystems, install-cooldown gate, supply-chain posture), `header-audit waste` (usage accounting from your own session transcripts — MCP servers and skills you pay for but never use, tool error rates, compaction pressure, the always-loaded skill context tax), and `header-audit rails` (determinism guardrails — pre-commit gate, test ratchet, compounding memory).
2. **Fetches the latest briefing** for the resolved topic (arg > personal `REPO_TOPIC` > committed `TEAM_TOPIC` > the built-in public default). With no custom topic, the default fetches and **merges both public topics — `Self Improving Agent` + `Agentic Coding`**; setting `HEADER_DEFAULT_TOPIC` (or a binding) replaces them with your one topic.
3. **Cross-references** the briefing's `key_developments` + `summary` against your actual stack (read from package manifests, `CLAUDE.md`, README, recent git activity).
4. **Surfaces unified recommendations** — a scorecard plus a ranked list. Findings split into **apply-now** (deletions, the supply-chain gate, security patches — deterministic, low-risk) and **`[Experiment]`** _(beta)_ — changes whose payoff must be proven (model swaps, major upgrades, behavioral rewrites). For these, `header-experiment` (see below) runs a local A/B against your tasks; the skill itself doesn't auto-experiment yet. It also surfaces opinionated **determinism rails** — guardrails Header endorses for AI-written code (a pre-commit gate, a test ratchet, compounding memory) — and offers to install them; the pitch is **prose asks, a guardrail enforces** (a `CLAUDE.md` rule the agent might forget vs. a hook that can't be skipped).
5. **Offers to implement** the apply-now items right there.

Your project data never leaves the machine — the audit and the cross-reference are local; only the briefing is fetched from `joinheader.com`.

After the audit, in interactive sessions, the skill offers to **customize the enrichment topic for this repo** (the briefing came from a generic agentic-coding feed; a custom topic targets sources about *your* stack). That offer fires once per repo. Subsequent runs in the same repo just run the audit with the bound topic.

### Output modifiers

Add a short word at the end to switch what gets shown — the audit always runs underneath:

| Modifier | Shows |
|---|---|
| `summary`, `tl;dr`, `short` | Just the briefing's `summary`. No audit output. |
| `sources`, `links` | Just the briefing's `source_articles`. No audit output. |
| _none_ (default) | Full output: scorecard + audit + briefing-enriched recommendations. |

### Cost analytics (beta)

```
/header cost
```

The first piece of the optimization platform: a local "billing meter" that reports your **measured** token spend. It reads usage JSONL — or your raw Claude Code transcripts directly:

```bash
find ~/.claude/projects -name '*.jsonl' -exec cat {} + | header-cost report
```

`report` ranks spend by model — real token counts × verified prices, with cache writes priced by their real 5-minute/1-hour duration and legacy Opus (3.x/4.0/4.1) priced apart from current Opus. It does **not** guess what switching models would save: a price re-rating of the same tokens is a projection, not a measurement, so `header-cost savings` only points at the experiment loop (`header-experiment`, below) that would actually prove a switch. Prices drift, so the skill **verifies them before quoting figures** (`header-cost refresh` from a served `HEADER_PRICES_URL`, or a fetch of current Anthropic pricing into `~/.header/prices.tsv`), and `report` always prints which prices it used and how fresh.

### Experiments (beta — local by default)

The audit feeds the experiment. When the audit surfaces an `[Experiment]` finding (model swap, prompt-debt deletion, dep upgrade), the skill scaffolds a runnable spec with one command — no editor homework:

```bash
# Prompt-debt deletion (auto-derived from a header-audit HIT — file + line numbers
# come straight from the audit finding):
header-experiment new <id> \
  --kind prompt-debt-deletion \
  --file CLAUDE.md --lines 12,13,14 \
  --task "Refactor a function — keep tests green." \
  --verify "npm test" --ledger-key <key>

# Or a model swap:
header-experiment new <id> --kind model-swap --from claude-opus-4-7 --to claude-sonnet-4-6 \
  --task ./tasks/refactor.md

# Then:
header-experiment validate <id>
header-experiment run <id> --aa     # noise-floor / harness check FIRST
header-experiment run <id>          # the A/B
header-experiment analyze <id> && header-experiment report <id>
header-experiment merge <id>        # if verdict = "B wins" — applies arm B's overrides
header-experiment push <id>         # opt-in: sync lineage + verdict to your account (API key)
```

Each `(task × arm × replicate)` runs in an isolated `git worktree` at a pinned commit; `--aa` validates the harness has no ordering / cache-warmup / drift confound before you trust any A/B. DB-touching experiments can provision an isolated database per experiment (or per run) via `setup:` / `teardown:` spec keys — the connection info is injected into both the agent and the verifier, and teardown is guaranteed even on Ctrl-C. Stats: paired-by-task **bootstrap 95% CI on per-task cost differences**, with **success rate non-inferiority** (lower CI bound ≥ −δ, default δ = 2%) as the merge gate. Verdict is one of `B wins (cost lower, success non-inferior)` / `A wins` / `no proven win` / `data degenerate` (N=1) / `A/A BIASED` (with a `WIDE CI / LIMITED POWER` caveat at 2–4 paired tasks) — the report prints the **conservative savings rate** (`max(0, -upper_CI(diff_cost))`) so the number you quote survives an audit. `merge` refuses to apply anything other than a B-wins verdict (`--force` overrides), shows a unified diff before writing, and prints a suggested `git commit` with the `Header-Audit-Finding:` trailer when the experiment came from an audit finding.

`new` auto-detects your verify command from `package.json` / `Cargo.toml` / `pyproject.toml` / `go.mod` / `Gemfile`. Pass `--task` as either a file path (relative to the repo) or a one-line inline prompt (written to `<exp_dir>/tasks/t1.md` automatically). For full control there's a generic flow: `--arm A:model[:overrides_dir] --arm B:model[:overrides_dir]`.

**Sync to your account (automatic when a key is present).** Every lifecycle change — define, edit (`validate`), run, analyze, merge — syncs the experiment's *lineage, status, and verdict* to your Header account so it shows up in the web UI: which experiment, testing which hypothesis, from which goal/topic/briefing, on which repo and machine, and how it came out, with a last-known status (`defined → run → analyzed → merged`). No per-edit prompt — configuring an API key is the opt-in; **no key → a one-time per-experiment nudge to connect an account.** It's the only egress in the experiment loop, and it's **metadata only**: arm models, override **paths**, task **titles** (authored, or a safe one-line summary derived from the prompt's first heading) + a sha256, and the analyzed result. **Prompt bodies, override file contents, and agent logs never leave the machine.** Turn it off with `header-config set experiment_sync off`; preview the exact JSON with `header-experiment push <id> --dry-run`. _(The receiving endpoint is landing server-side; until then sync exercises the call, saves locally, and retries on the next edit.)_

Out of scope for now (planned in [ROADMAP](ROADMAP.md)): mining tasks from git history (so the user doesn't author task prompts at all), σ-based power analysis (the current `<5 paired tasks → underpowered` cutoff is a heuristic), LLM-judge verifiers, and **anonymized cross-customer** aggregate submission of effect sizes (distinct from the account-scoped `push` above). The runner is local by design — experiments execute on your machine; only the explicit `push` leaves, and only metadata.

**Billing basis:** the `$` figures are **API (pay-per-token) rates** (the tool says so). On a Claude subscription (Pro $20 / Max $100 / $200 a month) you don't pay these — the `$` is a shadow/API-equivalent number and your real constraint is **usage limits**, so spend reads as cap consumption rather than dollars off a bill.

### Browse public topics

You can also ask the skill to browse Header's public topic catalog instead of using the default topic. Public topics span a variety of technology areas and each has its own curated source list and briefing history.

Ask the agent to list available topics or pick a specific one by name or ID — its briefing becomes the new enrichment source.

### Custom topics (API key required)

For audits enriched by a topic tuned to your specific project, you need a free Header account. The skill's audit-led flow offers to set this up after your first run; you can also do it yourself:

1. Sign up at [joinheader.com](https://joinheader.com) — free trial, no credit card
2. Create an API key with **read + write** access from **Settings ▸ API Keys** (write is required to create custom topics)
3. Make the key available to the skill — either export it:

   ```bash
   export HEADER_API_KEY="hdr_sk_..."
   ```

   or let the post-audit flow save it to `~/.header/credentials` (a file readable only by you).

With an API key, the skill can:

- **Create custom topics** with goal descriptions tailored to your project (drafted from the audit's stack detection)
- **Generate briefings on demand** for any of your topics
- **Update goals** to refine focus areas and keywords over time
- **Auto-tune** the goal based on which recommendations you apply (opt-in via `auto_tune`)
- **Check briefing status** for async generation (`IN_PROGRESS`, `COMPLETED`, `FAILED`)

### Per-repo topic memory

When you accept the post-audit custom-topic offer in a repository, the skill remembers the topic for that repo. After that, running `/header` in the same repo automatically uses your topic instead of the public default — no argument needed. Bindings live in a local registry (`~/.header/repos.jsonl`) keyed by the repo's git remote (with a path fallback); nothing is written inside your repo and nothing is sent. New sessions also check whether a newer briefing has appeared and surface it. Disable with `header-config set repo_memory false`; forget one repo with `header-repo clear`.

You can also put a repo's topic on a **schedule** (every 3 / 7 / 14 / 30 days). Header then regenerates the briefing server-side on that cadence, so a fresh one is waiting the next time you open a session — even if you never trigger it manually.

The personal binding above stays on your machine. To share a topic with a **whole team**, commit a [`.header/config`](#team-config-headerconfig) — teammates inherit it on clone with no setup.

## Configuration

Configuration comes from four places, highest priority first: **environment variable › committed team config (`<repo>/.header/config`) › personal config (`~/.header/config`) › built-in default**. Environment variables always win; a committed team config lets a whole repo share settings (see [Team config](#team-config-headerconfig)).

### Environment variables

| Variable | Description |
|----------|-------------|
| `HEADER_API_KEY` | Header API key (`hdr_sk_...`) for authenticated workflows. Only needed for custom topics and on-demand briefing generation. |
| `HEADER_LANGUAGE` _(Beta)_ | Language for output rendering (e.g. `Turkish`, `Spanish`). Defaults to English. The agent translates the presentation; API content stays English. |
| `HEADER_DEFAULT_TOPIC` | A single topic UUID used when no argument, repo binding, or team topic applies. Unset (the default): both public topics — "Self Improving Agent" + "Agentic Coding" — are fetched and merged. Setting it replaces the pair. |
| `HEADER_STALENESS_DAYS` | Maximum briefing age (in days) before the audit flags the enrichment briefing as stale. Defaults to 7. |
| `HEADER_HOME` | Override the state directory. Defaults to `~/.header`. |
| `HEADER_NONINTERACTIVE` | Set to `1` for scheduled / unattended runs so onboarding prompts are suppressed (`CI=1` is treated the same way). |

### Persisted config (`~/.header/config`)

`bin/header-config` reads and writes a flat `key: value` file at `~/.header/config`, so a preference set once survives across sessions without re-exporting an environment variable. The skill's preamble calls it for you; to set a preference by hand, call the helper inside the installed skill folder:

```bash
~/.claude/skills/header/bin/header-config set language Turkish
~/.claude/skills/header/bin/header-config list
```

Recognized keys: `default_topic`, `language`, `staleness_days`, `auto_update`, `update_check`, `ledger`, `telemetry`, `auto_tune`, `repo_memory`, `experiment_sync`, `aggregate_submit`. Run the helper with `defaults` to see every key and its default value.

### Team config (`.header/config`)

To share a topic (and a couple of settings) with a whole team, **commit a `.header/config` at the repo root**. Every teammate's skill reads it automatically on clone — no per-person setup — and it sits above each developer's personal `~/.header/config` but below their own env vars and explicit per-repo bindings. The skill offers to create and commit it for you right after you make a topic in a shared repo; it's recommended for shared repos and optional when you're solo.

Keep it to **team-relevant settings only**. Only an allow-list is honored: `default_topic`, `staleness_days`, `schedule_frequency_days`, `language`. Consent, update, and egress keys (`telemetry`, `auto_update`, `auto_tune`, `update_check`, `experiment_sync`, `aggregate_submit`) are **ignored** from a committed file by design — they stay personal, so a pushed change can never flip a teammate's privacy, trigger code, or enable account sync. The file is read as data only, never sourced.

```bash
~/.claude/skills/header/bin/header-config team-init <topic-uuid>   # scaffold ./.header/config
~/.claude/skills/header/bin/header-config team-set staleness_days 14
~/.claude/skills/header/bin/header-config team-show                 # honored vs ignored keys
git add .header/config && git commit -m "Add Header team config"
```

### State directory

The skill keeps a small amount of state under `~/.header/` (override with `HEADER_HOME`):

| File | Purpose |
|---|---|
| `config` | Persisted configuration (flat `key: value`). |
| `credentials` | Optional — your API key, saved by the post-audit flow (`chmod 600`; read as data, never executed). |
| `.welcome-seen`, `.signup-state`, `.language-prompted`, `.telemetry-prompted`, `.autotune-offered` | Global onboarding markers, so machine-wide first-run prompts show exactly once. |
| `last-update-check`, `update-snoozed`, `version-info.json` | Update-check cache, snooze state, and the last version-endpoint response. |
| `ledger.jsonl` | Recommendation ledger (applied/dismissed/snoozed/wanted) — the file stays local. (Experiment sync includes *one* finding's provenance — its title/topic/briefing/source — for the experiment being synced; never the whole ledger.) |
| `telemetry.jsonl` | Local usage events — only written if you opt into telemetry. |
| `installation-id` | Random per-machine UUID. Used as the machine id in experiment sync (and by full-tier telemetry); not tied to your identity. |
| `experiments/<id>/` | Local experiment specs, runs, and results. Stay on the machine; when an API key is present, each lifecycle edit auto-syncs *metadata only* (lineage + status + verdict) to your account — never prompt bodies, override contents, or logs. Disable with `header-config set experiment_sync off`. The `.last-sync` marker records the last sync result. |
| `repos.jsonl` | Repo → topic bindings (which custom topic each repository uses) — local-only, never sent. |
| `repo-seen/` | Per-repo "last briefing seen" markers, for the session-start freshness check. |
| `repo-flags/` | Per-repo onboarding flags (e.g. `topic-offered`, `schedule-offered`) so those offers fire once **per repo** — every repo can get its own tailored topic and schedule. |
| `prices.tsv` | Optional — token price overrides for `header-cost` (per family or per model id). Built-in defaults are used if absent. |
| `prices-cache.tsv` | Optional — price table fetched by `header-cost refresh` (validated). Sits between defaults and your override. |

## Updating

On each run the skill checks for a newer version against Header's version endpoint (cached; 5-second timeout; silent and harmless if the endpoint is unreachable). When a newer version is available it offers to update, and remembers your choice:

- **The prompt** offers Yes / Always / Not now / Never. "Always" sets `auto_update`; "Never" sets `update_check false`.
- **Auto-update:** `~/.claude/skills/header/bin/header-config set auto_update true` — future updates install silently.
- **Disable checks:** `~/.claude/skills/header/bin/header-config set update_check false`.
- **Update manually anytime** by re-running your installer — `npx skills add Header-inc/Header-skill -g` (Option A), or the script:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
  ```

If Header ships a breaking API change, the version endpoint marks a minimum supported version; a skill older than that says so rather than failing silently. Updates install atomically and roll back on failure.

## Telemetry

Telemetry is **off by default** and opt-in. The skill asks once during onboarding; change it any time:

```bash
~/.claude/skills/header/bin/header-config set telemetry off|anonymous|full
```

- **off** — nothing recorded or sent.
- **anonymous** — aggregate usage only, no identifier.
- **full** — usage plus a random install id (not derived from your identity); if an API key is set, full-tier sends are authenticated so usage ties to your account.

**Sent:** which path ran, outcome, duration, skill version, OS, and how many recommendations you surfaced/applied. **Never sent:** your code, file paths, repo or branch names, or briefing content — the recommendation ledger and the workspace audit stay on your machine. Sends are rate-limited, fail-safe, and stripped of local-only fields before they leave.

## Development

The skill is plain `bash` — the test suite has no dependencies:

```bash
cd header && ./test/run.sh
```

Enable the pre-commit hook once per clone so the suite runs — and blocks — on every commit:

```bash
git config core.hooksPath .githooks
```

## License

MIT — see [LICENSE](LICENSE) for details.
