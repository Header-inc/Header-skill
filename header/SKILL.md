---
name: header
version: 0.36.0
description: "Audit and optimize the AI coding agent's own setup — CLAUDE.md, model choice, dependencies, settings — for prompt-config debt and supply-chain risk. Each invocation runs the audit, enriched by the latest agentic-coding briefing relevant to your stack. Also captures session learnings natively: '/header wrapup' (or '/header compound') reviews the session and writes the pitfalls/learnings worth keeping into committed .claude/memory/ — the compounding-memory flywheel, run by Header instead of a separate skill. Public access needs no auth; authenticated workflows use an API key."
when_to_use: "Use to audit and improve the agent's own setup. Triggers include audit, audit my setup/agent/harness, optimize codebase, reduce token cost, supply-chain risk, dependency upgrade, CLAUDE.md or prompt debt, add a pre-commit hook / guardrails / determinism rails, test ratchet, compounding memory / capture learnings, latest best practices, what's new in agents/MCP/coding tools. Runs on /header, /header-audit, or the legacy /header-briefing. Run '/header wrapup' at session end — or '/header compound' anytime (mid-session after something breaks/works, or at the end) — to review the session and capture its learnings/pitfalls into committed .claude/memory/ so future sessions stop re-hitting them; triggers include wrap up, wrapup, session retro/wrap-up, capture learnings, what did we learn, note the pitfalls, compound, remember this for next time. Pass a topic name, UUID, or briefing URL to swap the enrichment topic; otherwise the default agentic-coding topic is used. Run '/header fable-5' (or 'adopt') for the engine-adoption card — a grounded 'should you move your harness to Fable 5 / a newer model?' answer that hands off to a model+effort experiment (header-experiment mine --adopt); '/header opus-4.8' renders the Opus 4.8 card (the same-price move)."
argument-hint: "[topic-name-or-uuid-or-briefing-url]"
allowed-tools: Bash, AskUserQuestion
---

*The `when_to_use`, `argument-hint`, and `allowed-tools` frontmatter fields are honored by Claude Code; other harnesses ignore them safely.*

*Deep / rarely-hit material lives in `reference/*.md` next to this file (loaded on demand, not every run). When a section points at **`reference/X.md`**, read it then — `cat "$(dirname "$HEADER_BIN")/../reference/X.md"` — only when that path actually fires.*

# Header — audit & optimize the coding agent

[Header](https://joinheader.com) is an optimization layer for AI coding agents. Every invocation of this skill runs a **local audit** of your agent harness — `CLAUDE.md`, model choice, dependencies, settings — for prompt-config debt and supply-chain gaps, and **enriches the recommendations** with the latest agentic-coding briefing for the resolved topic. The audit is local and read-only; nothing about your project leaves the machine. Briefings come from Header's public API (no auth) or a custom topic you own (API key).

> This skill uses `curl`, so it runs in any agent with shell access (Claude Code, Cursor, Aider, OpenAI Codex CLI, Goose, etc.). Claude Code users may substitute `WebFetch` for the read-only GETs if they prefer.

## Preamble (run first)

Run this block before anything else. **Claude Code substitutes `{SKILL_DIR}`** with the absolute path of the directory containing this `SKILL.md` (the skill's base directory, provided on invocation). Other agents: replace `{SKILL_DIR}` with the path of the folder you loaded this file from. If you cannot determine it, leave the token — the fallback paths handle it.

```bash
# --- Header skill preamble - run before anything else ---
_HC=""
for _d in "{SKILL_DIR}" "$HOME/.claude/skills/header" \
          ".claude/skills/header" "$HOME/.codex/skills/header" \
          ".agents/skills/header"; do
  [ -x "$_d/bin/header-config" ] && { _HC="$_d/bin/header-config"; break; }
done
# Self-heal: a Codex / npx GitHub-download install can copy bin/* without the
# executable bit, so the -x test above misses an otherwise-complete install. If a
# header-config exists but isn't executable, repair the bin dir best-effort.
if [ -z "$_HC" ]; then
  for _d in "{SKILL_DIR}" "$HOME/.claude/skills/header" \
            ".claude/skills/header" "$HOME/.codex/skills/header" \
            ".agents/skills/header"; do
    if [ -f "$_d/bin/header-config" ] && [ ! -x "$_d/bin/header-config" ]; then
      chmod +x "$_d/bin/"* 2>/dev/null || true
      [ -f "$_d/test/run.sh" ] && chmod +x "$_d/test/run.sh" 2>/dev/null || true
      [ -x "$_d/bin/header-config" ] && { _HC="$_d/bin/header-config"; echo "HEADER_SELFHEAL: chmod +x $_d/bin"; break; }
    fi
  done
fi
if [ -z "$_HC" ]; then
  echo "HEADER_INSTALL: missing"
  echo "HEADER_NOTICE: full install required — run: npx skills add Header-inc/Header-skill -g  (or)  curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh"
else
  echo "HEADER_INSTALL: ok"
  echo "HEADER_BIN: $_HC"
  _HH="${HEADER_HOME:-$HOME/.header}"
  mkdir -p "$_HH" 2>/dev/null || true
  # Codex's filesystem sandbox (workspace-write) often excludes ~/.header, so
  # ledger/last-run/config writes fail silently. Probe once and tell the user the
  # remedy instead of letting persistence degrade invisibly. Normal shells: ok.
  if ( : > "$_HH/.writable-probe" ) 2>/dev/null; then
    rm -f "$_HH/.writable-probe" 2>/dev/null || true
    echo "HEADER_STATE: ok"
  else
    echo "HEADER_STATE: readonly"
    echo "HEADER_NOTICE: $_HH is not writable (Codex sandbox?) — ledger, config and run markers won't persist. Fix: add $_HH to the sandbox's writable roots, or set HEADER_HOME to a writable path (e.g. export HEADER_HOME=\"\$PWD/.header\")."
  fi
  if [ -n "${CI:-}" ] || [ -n "${HEADER_NONINTERACTIVE:-}" ]; then
    echo "INTERACTIVE: no"
  else
    echo "INTERACTIVE: yes"
  fi
  _HR="$(dirname "$_HC")/header-repo"
  _TEAM_CFG="$("$_HC" team-path 2>/dev/null || true)"
  _TEAM_TOPIC="$("$_HC" team-get default_topic 2>/dev/null || true)"
  _TEAM_LANG="$("$_HC" team-get language 2>/dev/null || true)"
  _TEAM_STALE="$("$_HC" team-get staleness_days 2>/dev/null || true)"
  echo "TEAM_CONFIG: ${_TEAM_CFG:-none}"
  echo "TEAM_TOPIC: $_TEAM_TOPIC"
  echo "DEFAULT_TOPIC: ${HEADER_DEFAULT_TOPIC:-$("$_HC" get default_topic)}"
  echo "REPO_TOPIC: $("$_HR" get 2>/dev/null || true)"
  echo "LANGUAGE: ${HEADER_LANGUAGE:-${_TEAM_LANG:-$("$_HC" get language)}}"
  echo "STALENESS_DAYS: ${HEADER_STALENESS_DAYS:-${_TEAM_STALE:-$("$_HC" get staleness_days)}}"
  echo "WELCOME_SEEN: $([ -f "$_HH/.welcome-seen" ] && echo yes || echo no)"
  echo "LANGUAGE_PROMPTED: $([ -f "$_HH/.language-prompted" ] && echo yes || echo no)"
  echo "SIGNUP_STATE: $(cat "$_HH/.signup-state" 2>/dev/null || echo unset)"
  echo "TELEMETRY_PROMPTED: $([ -f "$_HH/.telemetry-prompted" ] && echo yes || echo no)"
  echo "TOPIC_OFFERED: $("$_HR" flag topic-offered 2>/dev/null || echo no)"
  echo "SCHEDULE_OFFERED: $("$_HR" flag schedule-offered 2>/dev/null || echo no)"
  echo "TEAM_CONFIG_OFFERED: $("$_HR" flag team-config-offered 2>/dev/null || echo no)"
  echo "AUTOTUNE_OFFERED: $([ -f "$_HH/.autotune-offered" ] && echo yes || echo no)"
  if [ -n "${HEADER_API_KEY:-}" ] || { [ -f "$_HH/credentials" ] && grep -q '^HEADER_API_KEY=' "$_HH/credentials" 2>/dev/null; }; then
    echo "HAS_KEY: yes"
  else
    echo "HAS_KEY: no"
  fi
  _UPD="$("$(dirname "$_HC")/header-update-check" 2>/dev/null || true)"
  case "$_UPD" in UPDATE_*) echo "UPDATE_CHECK: $_UPD" ;; esac
fi
# --- end preamble ---
```

If `HEADER_INSTALL: missing` was echoed, print the `HEADER_NOTICE` line to the user and **stop**. The audit requires `bin/header-audit`; there is no fallback flow. Tell them to re-run after the install completes. (If the preamble echoed `HEADER_SELFHEAL:` it repaired exec bits an installer stripped — e.g. a Codex/`npx skills` GitHub download — and resolved the install automatically; no action needed.)

If `HEADER_STATE: readonly` was echoed, surface the accompanying `HEADER_NOTICE` once and **continue** — the audit still runs. Only local persistence degrades: the recommendation ledger, personal config, onboarding markers, and update snoozes won't be saved. This is common under Codex's `workspace-write` sandbox, which usually excludes `~/.header`; the remedy is to add `~/.header` to the sandbox's writable roots or point `HEADER_HOME` at a writable path.

If `HEADER_INSTALL: ok`, use the echoed values for the rest of the session:

| Echoed line | Use |
|---|---|
| `HEADER_BIN` | Absolute path to `bin/header-config`. Re-substitute it in any later bash call that needs the config CLI — each `Bash` invocation is a fresh shell. |
| `TEAM_CONFIG` | Path to the committed `<repo>/.header/config` (the team layer), or `none`. A path means this repo ships shared Header settings — see `reference/custom-briefings.md` (Team config). |
| `TEAM_TOPIC` | Topic UUID pinned by the committed team config, or empty. When non-empty **and** a key is available it sits above `DEFAULT_TOPIC` but below a personal `REPO_TOPIC` binding in topic resolution. |
| `DEFAULT_TOPIC` | Personal/global topic UUID — env var → `~/.header/config` → empty. Used when no argument, personal binding, or team topic applies. |
| `REPO_TOPIC` | Topic UUID this repository is **personally** bound to (via `header-repo`), or empty. When non-empty **and** a key is available, it wins over `TEAM_TOPIC` and `DEFAULT_TOPIC`. |
| `LANGUAGE` | Render user-facing output in this language. Resolves env → team config → personal config → `English`. |
| `STALENESS_DAYS` | Threshold for the briefing-age check. Resolves env → team config → personal config → `7`. |
| `INTERACTIVE` | `no` → scheduled / non-interactive run: skip every prompt. `yes` → all prompts are eligible. |
| `WELCOME_SEEN` | `no` (with `INTERACTIVE: yes`) → show the first-run welcome before the audit. |
| `LANGUAGE_PROMPTED` | `no` (with `INTERACTIVE: yes` and `LANGUAGE: English`) → show the first-run language prompt. |
| `SIGNUP_STATE` / `HAS_KEY` | Drive the post-audit custom-topic offer — see `reference/topics.md`. |
| `TELEMETRY_PROMPTED` | `no` (with `INTERACTIVE: yes`, after the post-audit flow resolves) → ask telemetry consent once. |
| `TOPIC_OFFERED` | **Per-repo** flag. `no` (with `INTERACTIVE: yes` and empty `REPO_TOPIC`) → offer to create a custom topic for *this* repo after the audit. Once per repo. |
| `SCHEDULE_OFFERED` | **Per-repo** flag. `no` (with a bound `REPO_TOPIC` not yet on a schedule, `INTERACTIVE: yes`) → make the schedule offer for *this* repo's topic. Once per repo. |
| `TEAM_CONFIG_OFFERED` | **Per-repo** flag. `no` (with `TEAM_CONFIG: none`, a team-shareable topic just created or bound, `INTERACTIVE: yes`) → offer to write and commit `.header/config`. Once per repo. |
| `AUTOTUNE_OFFERED` | Global. `no` (with a key, a custom goal, and 3+ applied recs, `INTERACTIVE: yes`) → make the one-time goal auto-tuning offer. |
| `UPDATE_CHECK` | `UPDATE_AVAILABLE old new` or `UPDATE_REQUIRED old min` → run the update flow (see "Staying up to date"). Absent when up to date, snoozed, or disabled. |

The echoed `DEFAULT_TOPIC` / `LANGUAGE` / `STALENESS_DAYS` already fold in **env var > `~/.header/config` > built-in default** — use them directly rather than re-reading env vars or the config file later.

## First-run onboarding

Runs **only with `INTERACTIVE: yes`**. On a scheduled / non-interactive run (`INTERACTIVE: no`), skip this section — print nothing, ask nothing.

**Claude Code only:** the choice below uses the `AskUserQuestion` tool. Other harnesses present the same options as a numbered list and ask the user to reply with a number.

### Welcome — before the audit

If `WELCOME_SEEN: no`, print this once, then continue:

> 👋 **Header** — I optimize AI coding agents. Each run I audit your harness (`CLAUDE.md`, model, dependencies) for prompt-config debt and supply-chain gaps, and check it against what's new in agentic coding. No account needed to start.

```bash
touch "${HEADER_HOME:-$HOME/.header}/.welcome-seen"
```

### Language — before the audit

If `LANGUAGE: English` (the built-in default) **and** `LANGUAGE_PROMPTED: no`, ask **once** which language to render output in:

> **Which language should output be rendered in?**
>
> Briefing content stays English on the wire; the agent translates the presentation for you. Translation quality varies by language; proper nouns, code identifiers, and URLs stay verbatim.

Options (label English as recommended):

1. **English** — recommended, no translation.
2. **Spanish** — agent translates the presentation.
3. **Turkish** — agent translates the presentation.
4. **Other** — ask the user which language to use.

Persist the choice and touch the marker (`<HEADER_BIN>` is the preamble's echoed path):

```bash
<HEADER_BIN> set language "Chosen"
touch "${HEADER_HOME:-$HOME/.header}/.language-prompted"
```

Replace `Chosen` with the user's pick. Persisting `English` explicitly is harmless. Always touch the marker so the prompt never fires again. Skip the prompt entirely if `INTERACTIVE: no` or `LANGUAGE_PROMPTED: yes`.

## Staying up to date

Driven by the preamble's `UPDATE_CHECK` line. Handle it **right after the preamble, before the audit** — an out-of-date skill may not work against the API. If there was no `UPDATE_CHECK` line, skip this section. Both branches use `<HEADER_BIN>`.

### UPDATE_REQUIRED — non-optional

`UPDATE_CHECK: UPDATE_REQUIRED <old> <min>` means the installed skill is older than the minimum the Header API still supports; calls may fail until it's updated.

- **Interactive**: tell the user plainly and offer to update now → **Run the update**. If they decline, warn that the audit may fail, then continue.
- **Non-interactive**: print one warning line ("Header skill v{old} is below the supported minimum v{min} — update soon") and continue. Never block a scheduled run.

### UPDATE_AVAILABLE — optional

`UPDATE_CHECK: UPDATE_AVAILABLE <old> <new>`. Skip entirely if `INTERACTIVE: no`.

If `<HEADER_BIN> get auto_update` returns `true`: skip the prompt, say "Updating the Header skill v{old} → v{new}…", and go to **Run the update**.

Otherwise ask (`AskUserQuestion` on Claude Code; numbered plain text elsewhere):

> Header skill v{new} is available (you're on v{old}). Update now?
>
> 1. **Yes, update now** (recommended)
> 2. Always keep me up to date
> 3. Not now
> 4. Never ask again

- **Yes** → **Run the update**.
- **Always** → `<HEADER_BIN> set auto_update true`, then **Run the update**.
- **Not now** → write an escalating snooze and continue:

```bash
_HH="${HEADER_HOME:-$HOME/.header}"; _NEW="<new>"; _LVL=1
if [ -f "$_HH/update-snoozed" ]; then
  read -r _v _l _ < "$_HH/update-snoozed" 2>/dev/null || true
  if [ "${_v:-}" = "$_NEW" ]; then
    case "${_l:-}" in [0-9]*) _LVL=$((_l + 1)); [ "$_LVL" -gt 3 ] && _LVL=3 ;; esac
  fi
fi
printf '%s %s %s\n' "$_NEW" "$_LVL" "$(date +%s)" > "$_HH/update-snoozed"
```

- **Never ask again** → `<HEADER_BIN> set update_check false`; mention they can re-enable with `header-config set update_check true`.

### Run the update

1. Read "what's new" from the cached release info:

```bash
cat "${HEADER_HOME:-$HOME/.header}/version-info.json" 2>/dev/null
```

2. Re-run the installer — fetches the latest, swaps the install atomically, rolls back on failure:

```bash
curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
```

(Working from a git clone? `git pull --ff-only && ./install.sh` instead.)

3. Clear the update cache:

```bash
rm -f "${HEADER_HOME:-$HOME/.header}/last-update-check" "${HEADER_HOME:-$HOME/.header}/update-snoozed"
```

4. Tell the user "Updated to v{new}" plus the `message` (and `notes_url` if present), then continue with the audit. If the installer reported a failure it restored the previous version — say so and suggest retrying.

The update takes effect on the **next** session — the current session keeps the already-loaded `SKILL.md` in context until then.

## Configuration

Configuration resolves in this order, highest priority first: **environment variable › committed team config (`<repo>/.header/config`) › personal config (`~/.header/config`) › built-in default**. None are required to run.

| Variable | Default | Description |
|---|---|---|
| `HEADER_API_KEY` | — | API key (`hdr_sk_...`) for authenticated workflows (custom topics, on-demand generation). |
| `HEADER_LANGUAGE` _(Beta)_ | `English` | Language for output rendering. API content stays English; the agent translates the presentation. |
| `HEADER_DEFAULT_TOPIC` | *(unset → built-in pair)* | A single topic UUID used when no argument, repo binding, or team topic applies. **Unset (the default): both public topics are fetched & merged — `1991163f-…` Self Improving Agent + `bf25c29e-…` Agentic Coding.** Setting it (or `~/.header/config default_topic`) replaces the pair with your one topic. |
| `HEADER_STALENESS_DAYS` | `7` | Maximum briefing age in days before the audit flags the enrichment briefing as stale. |
| `HEADER_TEAM_DIR` | git toplevel, else `$PWD` | Directory whose `.header/config` is read as the team layer. Override mainly for testing. |

## Default flow: audit + enrichment

Every invocation runs this flow. The audit is local and read-only; the briefing is fetched from Header for enrichment.

> **Mode routing:** the audit always runs. A short word at the end of the invocation switches **what gets shown**, not what gets done: `summary` → render only the briefing's `summary` field, no audit output; `sources` → only `source_articles`, no audit output; `add-source <url>` → see `reference/custom-briefings.md` (Add a source); `since-last` → see `reference/custom-briefings.md` (Since-last); `cost` → see `reference/cost.md`. Some arguments are special-cased to a *different* flow, not a display mode:
- `fable-5` (also `fable5`, `claude-fable-5`), `opus-4.8` (also `opus-4-8`), or `adopt` → render the **engine-adoption card** (see `reference/engine-adoption.md`), a self-contained "should you move your harness to this model?" answer — not a topic; bare `adopt` renders the newest snapshot (Fable 5).
- `wrapup` (also `wrap-up`, `wrap`) or `compound` → run the **session wrap-up / compound** flow (see "Session wrap-up & compound (`/header wrapup`, `/header compound`)"): review the session and capture its learnings/pitfalls into committed `.claude/memory/`. This does **not** run the audit — it's the session-end capture ritual. `wrapup` adds a short session recap first; `compound` is capture-only.

Anything else (a topic name/UUID/briefing URL, or no argument) runs the full audit-led flow below.

### Step 0 — Resolve the topic

The topic determines which briefing is pulled in for enrichment. Fallback chain (first match wins):

> **Engine-adoption short-circuit:** if the argument is `fable-5` / `fable5` / `claude-fable-5` / `opus-4.8` / `opus-4-8` / `adopt` (or a `<model>-adoption` keyword), this is **not a topic** — render the **engine-adoption card** (see that section) and skip Steps 1–4. The card reads a bundled snapshot + the user's detected engine, not a briefing.

1. **Explicit argument** — if the user passed an identifier:
   - URL containing `/briefings/<uuid>` → extract the UUID, treat as a **briefing ID**, skip Step 1, go straight to Step 2 with `/api/v2/public/briefings/<uuid>`.
   - URL containing `/topics/<uuid>` or a bare UUID → use as the **topic ID** and proceed to Step 1.
   - Anything else → search `/api/v2/topics/public/catalog` for a case-insensitive substring match on `name`. One match → use its `id`; multiple → ask to disambiguate; none → fall through.
2. **Personal binding for this repo** — if `REPO_TOPIC` is non-empty **and** `HAS_KEY: yes`, use it (it wins over `TEAM_TOPIC`). Bound topics are private — use the authenticated endpoints, and run the session-start freshness check (see `reference/custom-briefings.md` (Bound repos)). If `REPO_TOPIC` is set but no key is available, skip and fall through. A `404` means the topic was deleted server-side — offer `header-repo clear` and fall through.
3. **Team topic for this repo** — if `TEAM_TOPIC` is non-empty **and** `HAS_KEY: yes`, use it via the authenticated endpoints (same freshness check). Without a key, tell the user this repo pins a team topic that needs an API key (offer to sign up), then fall through. On `404` tell the user to fix `.header/config` (never auto-edit a committed file) and fall through.
4. **Resolved default topic** — `DEFAULT_TOPIC` if non-empty. This is an explicit override (env `HEADER_DEFAULT_TOPIC` or `~/.header/config`): a **single** topic that **replaces** the built-in pair below.
5. **Built-in public default — BOTH hardcoded topics (no auth).** When nothing above resolves, always enrich from **both** public topics:
   - `1991163f-be9c-4df2-a33c-046a4d1357e1` — **Self Improving Agent**
   - `bf25c29e-de97-46f2-9c46-47e4e9d75e40` — **Agentic Coding**

   Run Steps 1–2 for **each** id, then **merge** the two briefings for enrichment (see "Merging the default briefings" under Step 2). This is the default for every no-argument, no-key run. (A single topic resolved in 1–4 is unchanged: one briefing, no merge.)

**Claude Code only:** the explicit argument is delivered as `$ARGUMENTS` when invoked via `/header <topic>`. Other harnesses: extract the topic identifier from the user's message text.

### Step 1 — Get the latest briefing ID

*Skip if Step 0 resolved a briefing ID directly.* When Step 0 resolved the **built-in two-topic default**, run Steps 1–2 **once per topic id** and keep both `latest_briefing.id`s.

```bash
curl -sS --retry 1 -w "\n%{http_code}" \
  https://joinheader.com/api/v2/topics/public/{topic_id}
```

Extract `latest_briefing.id`.

### Step 2 — Fetch the full briefing

```bash
curl -sS --retry 1 -w "\n%{http_code}" \
  https://joinheader.com/api/v2/public/briefings/{briefing_id}
```

From the JSON, pull `summary`, `source_articles` (title + url), and `generated_at`. **The content lives in `summary`** — a markdown doc whose "Key Insights" / bolded developments are what you cross-reference in Step 4. (`key_developments` is typically empty; don't depend on it.)

**Staleness:** compare `generated_at` to today. If older than `${HEADER_STALENESS_DAYS:-7}` days, prepend a one-line warning to the audit output. With an API key, suggest re-triggering generation via `POST /api/v2/goals/{goal_id}/briefings`.

**Merging the default briefings (two-topic default only).** When you fetched both public topics, pull `summary` / `source_articles` / `generated_at` from each, then combine: read both `summary` markdowns for developments and concatenate `source_articles`, then **de-duplicate** near-identical items (same headline, or same source URL), keeping one. When the origin matters, label a surfaced item with its topic (*Self Improving Agent* / *Agentic Coding*). Apply the staleness check **per briefing** — warn if **either** is older than `${HEADER_STALENESS_DAYS:-7}` days, naming which. For the `summary` / `sources` output modes on the two-topic default, show **both** (each labeled by topic). A single resolved topic (Steps 1–4) is unchanged: one briefing, no merge.

### Step 3 — Run the audit

Local, read-only — nothing leaves the machine. Run **all seven** scans. `<AUDIT>` is `header-audit`, in the same `bin/` dir as the preamble's `HEADER_BIN`.

```bash
<AUDIT> harness          # CLAUDE.md / AGENTS.md (+ @imports) / settings / hooks / skills / commands / subagents / MCP / Bash posture / model staleness / stale refs
<AUDIT> deps             # ecosystems / tool versions / install-cooldown gate
<AUDIT> cost             # spend-by-model from your real transcripts → top model-routing candidate
<AUDIT> waste            # usage accounting from the same transcripts: unused MCP servers / skills, tool error rates, compaction pressure, skill context tax
<AUDIT> rails            # determinism guardrails present|absent (pre-commit gate / test ratchet / compounding memory) — opinionated, additive
<AUDIT> retro            # behavioral mining of your own sessions: edit-thrash, gotcha volume, git-workflow tells, ranked capability nudges (worktree / guardrail / compound) — the coach lead
<AUDIT> grade            # composite setup grade (e.g. B+) over the 5 scorecard axes — composites harness+deps+rails internally; static-config only, deterministic
```

**Briefing-supplied patterns (run before `harness`).** The 8 prompt-debt patterns are built in, but the briefing can ship new ones without a skill release. If the fetched briefing names additional cargo-cult / debt phrases (a `debt_patterns` field, or patterns called out in the `summary`), write them to `${HEADER_HOME:-$HOME/.header}/patterns.tsv` *before* running `harness` — one `id<TAB>regex<TAB>why` per line — and the scan picks them up as `HIT`s with your ids. **Proven rows:** when the briefing carries cross-customer evidence for a pattern (a measured effect from the proven-changes library), write a 6-field row instead — `id<TAB>regex<TAB>why<TAB>effect<TAB>n_repos<TAB>ci` — and `harness` re-emits the evidence as a `PROVEN` line (a proven row may reuse a built-in id to attach evidence to it; the scan de-duplicates by id, first wins). Keep regexes conservative (`grep -iE`); malformed lines (not exactly 3 or 6 tab fields, or a non-integer `n_repos`) are skipped. This is how the distribution wedge feeds new hypotheses — and proven library results — into the deterministic scanner.

What the scans emit — and how to read each line — is documented under **"What the audit scans"** below. Capture the output and the line types (`FILE`, `IMPORT`, `NESTED`, `MODEL`, `MODEL-STALE`, `MODEL-UPGRADE`, `HIT`, `STALE-REF`, `HOOK`, `SKILL`, `SECURITY`, `ECOSYSTEM`, `TOOL`, `GATE`, `COST-SCOPE`, `COST-INPUT`, `COST-HARNESS`, `COST-NOTE`, `SPEND`, `ROUTE-CANDIDATE`, `WASTE-SCOPE`, `WASTE-INPUT`, `TOOL-USE`, `MCP-SERVER`, `MCP-UNUSED`, `SKILL-USE`, `SKILL-UNUSED`, `ERROR-RATE`, `COMPACTIONS`, `SKILL-TAX`, `CONTEXT-TAX`, `RETRO-SCOPE`, `RETRO-INPUT`, `RETRO-WINDOW`, `RETRO-HARNESS`, `RETRO-THRASH`, `RETRO-FAILS`, `RETRO-GIT`, `RETRO-SHIP`, `RETRO-PEAK`, `RETRO-PLAN`, `RETRO-CORRECTION`, `RETRO-CORR`, `RETRO-GAP`, `RETRO-CAP`, `GRADE`, `GRADE-AXIS`); you'll join them with the briefing in the next step. Lines that can become recommendations end with a **`key=<canonical-key>`** field — the pre-minted recommendation-ledger key. Use it verbatim; never invent a different one (see "Recommendation ledger").

### Step 4 — Cross-reference and present

The audit's findings + the briefing's items become a ranked list — but the **front door is the coach, not the config audit.** Render the default `/header` output as a **coach lead** (this subsection), then the existing scorecard + config recommendations as the **audit tail** below. The session-review feedback was unambiguous: what lands is *behavioral* (what happened, what to learn, what to do differently); what falls flat is config-artifact accounting (line counts, gates, dollar tables). So lead behavioral, demote config.

#### Coach lead — render first, in this fixed order

Built from `<AUDIT> retro` (+ your own session context). Heading: `## 🧭 Header — <repo basename>`. `RETRO-HARNESS` says these read **Claude Code** transcripts — if the preamble's active harness isn't `claude` (e.g. Codex), say the behavioral read is *historical Claude sessions*, not your current harness (Codex coverage ships with the Codex install).

**Proportional to signal — the #1 rule.** A thin window (few sessions, no `RETRO-CAP` fired, clean fails) gets a **short** lead: 2–3 lines total, then hand straight to the audit. **Don't narrate emptiness** — a quiet log earns a quiet lead, not paragraphs explaining why there's little to say. Length tracks signal; when in doubt, cut.

1. **Position — wrapup or setup.** *Wrapup*: substantial work already happened in *this* session (it's in your context) → open with what this session did, and close the lead by offering `/header compound` to capture its learnings. *Setup*: a fresh session → open with the week's pattern from the transcripts. A session with prior tool use is a wrapup. (If `<AUDIT> retro` returned only a `NOTE` — no transcripts for this repo yet — skip the week read; do the session-context parts and say machine-wide history is available via `retro --all-projects`.)

2. **This week, in one read** — open with **one** hook line (never a section): `🧭 <archetype> · <RETRO-PEAK> · <RETRO-SHIP> commits` (archetype = burst vs marathon from the session mix). Then 2–4 plain lines: sessions (`RETRO-WINDOW`), what shipped (`RETRO-SHIP` commits / LOC), what the work was about. No token counts here.

3. **⚠️ Gotchas & pitfalls** — `RETRO-FAILS` volume + the *actual* failing moments (your own session context for a wrapup; the recent transcript otherwise). Each: what bit, the one-line fix; if the learning is durable, note `/header wrapup` would capture it. `RETRO-FAILS` 0 errors → "clean week," don't invent gotchas to fill the section. `RETRO-CORRECTION` (user redirects) are the strongest `feedback_` candidates — name them and offer `/header wrapup` to capture them. `RETRO-GAP` (fixes claimed with no test run) is its own pitfall — name it and suggest asking for proof or the `precommit-gate` rail (`key=cap-verify`).

4. **🎯 Best practices for you — ranked by `RETRO-CAP`** (emission order = order of demonstrated need; render only the caps that fired). `worktree` → recommend git worktrees, citing the branch-juggling count. `guardrail` → recommend `<AUDIT> rail precommit-gate`, citing the failed-call count (if `RAIL precommit-gate` is already present, **affirm** it, don't re-pitch). `compound` → recommend `/header wrapup` + seeding `.claude/memory/`, citing the gotcha count + absent memory. All `[Apply with review]`; use each `key=cap-<name>` verbatim in the ledger. A weak cap (low count) → rank it low and **say it's weak**; never hard-sell — that anti-upsell discipline is exactly what the Fable-5 card got wrong. Also `RETRO-PLAN`: a low plan-mode rate → nudge plan-first for multi-file / migration work — `RETRO-CORR`, when present, quantifies it (planned vs unplanned error rate).

5. **🧪 Bigger experiments** *(opt-in depth)* — one or two `[Experiment]` items (model routing from `ROUTE-CANDIDATE`, engine adoption), framed "want me to prove it?" Below the practices, never above.

**One register, for everyone.** Plain language, lead with outcomes, no jargon dump. Keep the depth available (counts, ledger keys, experiment specs) but never let it crowd the lead — a line a non-engineer follows *and* an engineer trusts. Don't fork by audience; just be clear.

#### Audit tail — the config scorecard, demoted (still rendered)

After the coach lead, render the **setup grade + spend + scorecard + `[Apply now]` / `[Apply with review]` config findings** exactly as the contract below specifies (its heading stays `## 📊 Header audit`). It is the *tail*, not the lead. The RETRO-CAP rail practices already live in the coach lead (step 4) — **don't re-surface them here.** Keep it tight (the ranked-list cap applies). The one-line **setup grade** (`header-audit grade`'s `GRADE` line) is the scorecard's headline — a single glanceable mark for "how's my setup?"; spend sits directly below it, where the "open with the money" rule applies (not at the top of the report).

**Recent activity (diff-aware):** glance at recently-touched files (`git log --name-only --pretty=format: -15 2>/dev/null | sort -u`) and recent commit subjects (`git log --oneline -15 2>/dev/null`) to **weight audit recommendations** toward areas the user just changed. This is for the audit tail only — the **coach lead's "what shipped" comes from `RETRO-SHIP`** (a windowed count); don't narrate raw commit subjects from this glance up in the coach lead.

**Open with the money — but only spend that matches this repo and harness.** Before leading with any `SPEND` row, run the **scope + harness sanity check**: *does this spend source match the current repo and the current agent harness?* Read it off the markers `<AUDIT> cost` emits:

- **`COST-SCOPE repo`** + `COST-INPUT` → the spend is this repo's own transcripts. Safe to lead with and to turn into a ranked recommendation. (The default; nothing else aggregates silently.)
- **`COST-SCOPE global`** (only ever from an explicit `--all-projects`) → machine-wide spend across *all* projects. Present it as **background context only** — "across all your projects you've spent ~$X" — **never** as a ranked recommendation for *this* repo. Don't promote its `ROUTE-CANDIDATE` to an `[Experiment]`.
- **`COST-HARNESS codex …`** with a **`COST-NOTE harness-mismatch`** → the priced transcripts are *historical Claude Code* usage; the active harness is Codex, so this spend does **not** measure your current engine. Do **not** surface `ROUTE-CANDIDATE` as a model-routing `[Experiment]`. Say instead: *"No Codex cost data available; run a Codex 5.x paired experiment if you want to test model choice."* If you do mention the figures, label them explicitly as historical Claude Code usage only.

When the source *does* match (repo-scoped, harness `claude`), *lead* the scorecard with where the tokens actually go — "this period you spent ~$X; N% of it on `<top model>`" — using the `SPEND-TOTAL` / `SPEND` lines (always surface `header-cost`'s price-source + freshness line and the billing-mode note; see `reference/cost.md`). Then turn the `ROUTE-CANDIDATE` (the costliest model) into the headline **model-routing `[Experiment]`**: "route the low-stakes share of this spend to a cheaper tier — prove it before trusting the saving." This is the on-thesis hypothesis (model migration is the moat's first learning); it's a *candidate to prove*, never a projected saving — drive it with `header-experiment new --kind model-swap` (see `reference/experiments.md`). If `cost` returned only a `NOTE` (no usage history for this repo yet), skip the spend lead and say so in one line — mention `--all-projects` is available for machine-wide spend.

Build the unified list by combining:

- **Audit findings** — every `HIT` (prompt-debt pattern, built-in *or* briefing-supplied; when the pattern id carries a `PROVEN` line, cite the library evidence and skip the local experiment), `FILE` size signal (heavy always-loaded `CLAUDE.md`/`AGENTS.md` — **sum `FILE` + `IMPORT`ed files**, since @imports are loaded every turn too; `NESTED` files are on-demand, count them apart), `MODEL` mismatch / `MODEL-STALE` (pinned to a superseded tier → model-migration `[Experiment]`), `MODEL-UPGRADE` (a newer model shipped above the current one, e.g. Fable 5 above Opus 4.8 → offer the **engine-adoption card** (`/header fable-5`, or `/header opus-4.8` for the same-price move) and `header-experiment mine --adopt` to prove it — opportunity, not debt), `SECURITY` posture, `HOOK` (arbitrary shell on agent events — the biggest unguarded execution + supply-chain surface; treat an unexpected/opaque hook command as a security finding), `SKILL` (installed skills are a supply-chain surface — note any carrying `has-bin yes`, à la `/cso`), `STALE-REF` (a referenced path/script or @import that no longer exists), and `GATE absent` from `header-audit`.
- **Consistency findings** — `STALE-REF` lines are the deterministic half: surface each as `[Apply with review]` (fix the reference or delete the dead instruction). The other half is yours to judge — while reading `CLAUDE.md`/`AGENTS.md`, flag **mutually contradictory instructions** the greps can't catch (e.g. "use tabs" *and* "use spaces" for the same files; "always delegate to a subagent" *and* "never spawn subagents"; a rule that names a flag/command the tool no longer has). High-signal, low-risk — usually `[Apply now]` / `[Apply with review]`.
- **Briefing-derived recommendations** — developments in the briefing's `summary` (markdown) that touch the project's stack/tooling (read package manifests, lockfiles, language version files, build/test/CI configs, container/infra definitions, agent/skill definitions, `CLAUDE.md`, README), or that name a pattern the project doesn't yet use (or uses a now-legacy version of). The bias is toward **deletion** and toward changes the briefing endorses on the model currently configured. For a `MODEL-STALE` hit, cross-reference the briefing for the *current* recommended tier — the bin flags that it's stale; the briefing names what to move to.
- **Waste findings** — the highest-trust deterministic wins in the audit, because each is *measured from the user's own sessions* (see "`header-audit waste`"). `MCP-UNUSED` and repo-scope `SKILL-UNUSED` → `[Apply with review]` removals, stating the evidence window ("0 calls across N session files"); an unused MCP server's tool schemas are paid for on **every turn**, so this routinely outweighs any single prompt-debt `HIT`. `ERROR-RATE` rows are investigate-hypotheses (what keeps failing, and why). A non-zero `COMPACTIONS` count alongside a heavy always-loaded `FILE`+`IMPORT` sum is the strongest practical argument for the trim recommendations — name the connection. Put `CONTEXT-TAX` on the scorecard next to the always-loaded sum. Ledger keys are emitted on the rows themselves (`key=waste-mcp-<server>`, `key=waste-skill-<name>`).
- **Determinism-rail findings** — the absent `RAIL` rows (`<AUDIT> rails`, skip `n/a`) become **one** `[Apply with review] (opinionated — Header house guardrail, not measured on your repo)` recommendation, not one per rail: "add the determinism rails — *gate + ratchet + compound*." List the specific keys (`rail-precommit-gate` / `rail-test-ratchet` / `rail-compound-memory`) inside that single entry. Conviction, not an A/B; the new hook/file *is* the diff. (It'll show as a `HOOK` next `harness` scan — that's the rail you added, don't re-flag. See `reference/rails.md`.)
- **Known issues** — themes from learnings/post-mortems/runbooks/architecture-decision-records/incident reports + a quick `TODO`/`FIXME`/`HACK` density scan. A recommendation that addresses a known issue jumps the queue.

When a `MODEL` is known, cross-reference its model card / release notes before declaring a prompt-debt `HIT` actionable — confirm the pattern is *still* debt on that model. Prefer briefing sources for the cross-reference; fall back to the web.

**Present** the scorecard, then the ranked recommendation list. The shape below is a **contract, not an illustration** — same blocks, same axes, same order, every run, on every model (placeholders in `<angle brackets>`; everything else verbatim):

```markdown
## 📊 Header audit — <repo basename>

**Setup grade: `<GRADE letter>`** — <one clause: the heaviest `GRADE-AXIS` deduction, e.g. "supply-chain gate + rails absent"; or "clean, current setup" at A/A+>.

💰 **Spend** (this repo, last <COST-INPUT file count> transcripts — API-rate equivalent): **~$<SPEND-TOTAL usd> / <calls> calls**
- `<model>` — $<usd> (<share>%) ← costliest
- `<model>` — $<usd> (<share>%)

<header-cost's price-source + freshness line>. <billing-mode note: API → real dollars; subscription → usage-limit headroom, the % is identical; unknown → say so>.

| Axis | State |
|---|---|
| Model | `<MODEL>`<. Plus the MODEL-UPGRADE / MODEL-STALE note when one fired> |
| Always-loaded context | <FILE+IMPORT sum> tokens across <n> files; skills frontmatter +<CONTEXT-TAX est_tokens> tokens (<count> skills) |
| Security | Bash: <allowlist / denylist / bypass / no explicit policy>; hooks: <n configured / none> |
| Deps | <ECOSYSTEM names>; gates: <per non-n/a GATE: name present/absent><; TOOL too-old note if any> |
| Rails | <per non-n/a RAIL: name ✓ present / ✗ absent> |
```

Hard rules:

- **Setup grade** — the line directly under the heading shows the **letter only** from `header-audit grade`'s `GRADE <letter> <score> 100` line, rendered as `**Setup grade: <letter>**`. **Drop the numeric `<score>`/100** — the front-end (howsmyaicoding.com) shows just the letter; match it. **Never** model-assign or recompute the letter — it is deterministic by design (the website's "Setup grade B+" is this letter). Follow it with one short clause naming the heaviest `GRADE-AXIS` deduction (or "clean, current setup" at A/A+). The `GRADE-AXIS` breakdown rows (and the underlying score) are the *why* — surface them only if the user asks "why that grade?". Omit the grade line only if the scan emitted no `GRADE` row at all.
- **Spend block** — only when the scope + harness sanity check above passes (`COST-SCOPE repo` + `COST-HARNESS claude`). Otherwise replace the entire block with the single line that check prescribes (background-only global figure, harness-mismatch wording, or the no-data note) — never render the breakdown.
- **The table is fixed** — exactly these five axes, this order, as a GitHub-flavored markdown table (not a box-drawing table, not prose, not a different row set). An axis with nothing to report reads `—`. **Each cell is one short clause** — no paragraphs; detail belongs in the ranked list, not in the row.
- **Skip `n/a` rows** (gates, rails) everywhere, per the scan contracts.
- A due staleness warning is one line *above* the scorecard heading, nothing more.

Then the recommendations — each entry in exactly this shape, ranked by expected effect (the spend-led model-routing `[Experiment]` leads when the sanity check passed). **Keep the list to ~5 substantive items:** fold related findings into one (all absent rails → one; two weak/low-urgency experiments → **one parked line**, not separate entries). Each entry is **two lines max**:

```markdown
### Ranked recommendations

1. **[<Apply now | Apply with review | Experiment>] <imperative title>** — `<ledger-key>`
   **Where:** <file/manifest + line>. **Why:** <one sentence — the audit line or briefing item, link the source_articles URL>. <**Est:** <concrete expected effect> — OMIT this field entirely when there's no real estimate; never pad with "est."/"directional".>
```

`<ledger-key>` is the finding's emitted `key=` (see "Recommendation ledger") — showing it on every entry is how the user refers to an item and how the next run recognizes it. Sort findings into three buckets — the audit is not just a hypothesis generator, it's also a hypothesis *filter*:

- **`[Apply now]`** — strictly deterministic, low-risk: supply-chain gate, security patches, obvious bug fixes, doc typos. On the user's yes, make the edit (show a diff first; for the gate, write/append the `<AUDIT> gate ...` snippet to `.npmrc`). No verification beyond the diff.
- **`[Apply with review]`** — small-magnitude changes whose effect is observable from the diff alone: deletions of cargo-cult phrases (`as an AI language model`, `take a deep breath`, role puffery), trimming redundant role/persona boilerplate, doc cleanups, minor lint-style edits in CLAUDE.md / AGENTS.md. The user is the verifier — show the diff, get approval, apply. Optionally, run **one sanity replicate** (`header-experiment new --kind ... && header-experiment run <id> --k 1`) to confirm tests still pass; skip the full bootstrap A/B — the diff is the proof.
- **`[Experiment]`** _(beta)_ — only when the payoff is BOTH non-deterministic AND has enough magnitude to justify the experiment's own spend. Model swaps, subagent delegation toggles, fast-mode-instruction toggles, mandatory-skill rules, major framework migrations, behavior rewrites. If the user says "let's test that", **scaffold the spec from the finding payload** with `header-experiment new --kind ...` (see `reference/experiments.md`) — don't make the user retype what the audit already told us. The standard ledger dispositions apply per finding: `dismissed` if they reject this specific experiment, `wanted` if they want this one but aren't running it locally right now, `snoozed` for "not now."

**The dividing line between `[Apply with review]` and `[Experiment]` is a *ratio*, not a threshold.** What matters is **experiment cost vs. proven payoff** — and both sides are levers:

- **Magnitude lever** (the "is the change big enough?" side). Use the rough estimator from `header-audit harness` — each `FILE` row prints `<bytes>` and `<est_tokens>`. If the affected lines are **<~5% of the file's bytes** AND the diff is a faithful preview of the effect (a CLAUDE.md deletion: yes, the diff IS the change; a model swap or "always route X through subagent Y" rule: no — diff is one line, effect lives outside it), default to `[Apply with review]`.
- **Experiment-cost lever** (the "can we run it cheaply?" side). Even a tiny-magnitude question is fair game for `[Experiment]` if you make the experiment small:
  - **Cheaper model adapter.** For prefix-only experiments (CLAUDE.md edits, AGENTS.md tweaks), the agent's model isn't what's being tested — the prefix effect transfers across models. Run via Haiku: `--adapter "<wrapper that invokes claude --model claude-haiku-4-5 --print --output-format json>"`. Typically 5-10× cheaper than the user's default Opus.
  - **`--k 1`** when you want a sanity check, not a confidence interval. One replicate proves "this doesn't break," not "this is significantly better." Useful when paired with `[Apply with review]`.
  - **Narrower verify.** `pytest tests/v2/test_just_the_module.py -x -q` instead of the full suite — exercise only what the change can affect.
  - **Shorter task prompts.** A 10-turn focused task on a contained module gives the same statistical surface as a 76-turn coding marathon at ~7× less spend per replicate.

**Decision rule in one sentence:** if the change is small AND the diff is faithful → `[Apply with review]` (don't even run an experiment). If the change is large OR the diff is opaque → `[Experiment]` is warranted; *then* spend on the cost-lever side until the ratio is defensible.

**Quotable principle (don't lose this):** *don't run a $60 experiment to prove a $0.10 effect*. Experiments cost real tokens on API rates or real usage-limit headroom on a Claude subscription — either way, they're not free. Both magnitude and experiment-cost are levers; spend on either side until the ratio works.

**If you re-classify mid-flight, say so.** A finding's disposition (`[Apply now]` / `[Apply with review]` / `[Experiment]`) is a claim to the user. If you announce one and then act under another — e.g. you flagged `[Experiment]`, then on a closer look decide the diff is faithful enough to just apply — **state the change and your reason before you act**, and let the user redirect. Silently applying under a disposition other than the one you announced reads as sleight of hand, even when the new call is correct. The common case: you scope a CLAUDE.md trim as `[Experiment]`, then realize it's small *and* diff-faithful → `[Apply with review]`. Say that out loud; don't just quietly apply it.

**The apply menu.** After presenting, ask which recommendations (if any) to implement — one question, asked **alone**:

- **Claude Code:** a single `AskUserQuestion` call containing exactly one question. Never attach a second question to this call — the custom-topic offer, schedule offer, telemetry consent, and language prompt are each their own later step, in their documented order.
  - `question`: "Which recommendations should I implement now?" · `header`: "Apply" · `multiSelect: true`.
  - Options, in rank order, one per recommendation, at most **3** (the tool caps options at 4 and the last slot is reserved): `label` = the recommendation's `<ledger-key>`; `description` = one line — its disposition tag plus what changes where. More than 3 recommendations → say in the question text that the rest can be named via "Other".
  - Final option, always present: `label` "Just the report" · `description` "Change nothing now — everything stays in the ledger and is recognized next run."
  - "Just the report" selected together with recommendations → treat as a mis-tap: apply nothing, re-ask in plain text.
- **Other harnesses:** the same options as a numbered list (no cap); the user replies with numbers (comma-separated for several), or `0` / "none" for just the report.

On selection, implement the chosen recommendations in rank order in the current project. **An unselected option is not a dismissal** — leave it `surfaced`; only an explicit rejection in the user's words earns `dismissed` (see the ledger dispositions below).

**Commit signature.** When you (or the user) commit a fix that came from a recommendation the audit just surfaced, append a trailer to the commit message so the change's provenance is visible in `git log` / `git blame`:

```
Header-Audit-Finding: <ledger-key> — https://joinheader.com
```

Use the same `<ledger-key>` you logged to the recommendation ledger (the emitted `key=` for audit-derived findings, e.g. `gate-npm`, `delete-step-by-step`, `rail-precommit-gate`). Multiple findings landed in one commit → emit multiple `Header-Audit-Finding:` lines, one per key. Skip the trailer when the user is making unrelated commits in the same session; this trailer is for changes that originated from a specific Header audit finding. If the user is committing manually rather than asking you to commit, show them the trailer line and let them decide whether to include it.

**Output format detection** — adjust depth from modifiers in the user's invocation:

| User says | Show |
|---|---|
| "summary", "tl;dr", "short" | Just the briefing `summary`. No audit output. |
| "sources", "links" | Just `source_articles` (title + url). No audit output. |
| _none of the above_ (default) | Full output: scorecard + audit + briefing-enriched recommendations. |

**Output language:** render all user-facing output in `${HEADER_LANGUAGE:-English}`. Translate prose, headings, rationale; keep proper nouns, code identifiers, and URLs verbatim. API content stays English on the wire.

**Caching within a session:** hold the `briefing_id`(s) + `generated_at`(s) + the audit output in conversation context (the two-topic default caches both). On re-invocation in the same session, reuse it unless the user says "refresh", "latest", "new", or "re-audit".

### Recommendation ledger

Record each recommendation's disposition so future runs adapt. Skip when `<HEADER_BIN> get ledger` is `false`. `<LEDGER>` is `header-ledger`, in the same `bin/` dir.

**While surfacing recommendations:**
- **Audit-derived finding → the key is already minted.** Every scan line that can become a recommendation carries a final `key=<canonical-key>` field (`gate-pip`, `rail-precommit-gate`, `delete-step-by-step`, `route-<model>`, `adopt-<model>`, `trim-<file>`, `waste-mcp-<server>`, `stale-ref-<ref>`, `bash-allowlist`, …). **Use it verbatim — never rename, shorten, or re-mint it.** A per-run model-minted key fragments the ledger: the same finding resurfaces under a new name, `status` can't see its history, and dedup silently fails.
- **No audit line (briefing-derived or consistency finding) → mint once, reuse forever.** Before minting, run `<LEDGER> list` and reuse the existing key if any row is the same recommendation in substance (match on meaning, not exact title). Only when none exists, mint `<verb>-<object>` (lowercase, hyphenated, ≤4 words, e.g. `add-agents-md`) and keep that spelling on every re-surfacing.
- `<LEDGER> status <key>` — if `dismissed`, drop it. If `applied`, prefer a follow-up framing over re-recommending.
- `<LEDGER> list --action applied --since-days 30` — recently-adopted keys to proactively follow up on.
- Record each one you surface:

```bash
<LEDGER> record surfaced "<key>" --title "<short title>" --briefing "<briefing_id>" --topic "<topic_id>" --source "<source_url>"
```

**After the user chooses:**

```bash
<LEDGER> record applied   "<key>"    # implemented (or asked you to implement)
<LEDGER> record dismissed "<key>"    # explicitly rejected
<LEDGER> record snoozed   "<key>"    # "not now"
<LEDGER> record wanted    "<key>"    # an [Experiment] the user wants (and isn't running locally via header-experiment)
```

**Reset (start fresh after a finding-shape change).** When a Header update introduces new finding keys or retires old ones (e.g. the `cap-*` / `RETRO-*` coach findings, or the STALE-REF precision pass that orphaned the old false-positive `stale-ref-*` entries), the ledger can carry stale rows. `<LEDGER> reset` **archives** the current `ledger.jsonl` to a timestamped `.bak-*` (never destroys) and starts fresh. Offer it once, optionally — the canonical keys are stable, so this is a cleanup, not a requirement (see "Register — before the audit" for the one-time post-update prompt).

All ledger writes are best-effort, local-only, and never block the audit. They land under `${HEADER_HOME:-$HOME/.header}` (`ledger.jsonl`, `.last-run`, `credentials`, onboarding markers). Under a restrictive filesystem sandbox — notably Codex `workspace-write`, which usually excludes `~/.header` — these writes silently no-op; the preamble's `HEADER_STATE: readonly` line flags this, and the fix is to make `${HEADER_HOME:-$HOME/.header}` writable (add it to the sandbox's writable roots) or set `HEADER_HOME` to a writable path.

### Usage logging (run last in the audit flow)

After the audit + recommendations are delivered, log one usage event. `<TELEMETRY>` is `header-telemetry`, in the same `bin/` dir:

```bash
<TELEMETRY> log skill_run --outcome "<success|error>" --path "audit" --recs-surfaced <N> --recs-applied <N>
date -u +%Y-%m-%dT%H:%M:%SZ > "${HEADER_HOME:-$HOME/.header}/.last-run" 2>/dev/null || true
```

Records nothing unless the user opted into telemetry; only sends usage metadata — never workspace content. Best-effort.

### Fallback

On the built-in two-topic default, if **one** topic 404s, proceed with the other (note the miss in one line). If **both** default topics 404 — or a single resolved default topic does — browse the public catalog and pick a relevant topic:

```bash
curl -sS -w "\n%{http_code}" https://joinheader.com/api/v2/topics/public/catalog
```

## After the audit: customize your topic

In an interactive run, once per repo, offer to point the briefing at the user's stack (plus the chained bind / schedule / team-config offers). **Flow → `reference/topics.md`.**

## Telemetry consent

Ask **once**, only when `INTERACTIVE: yes`, `TELEMETRY_PROMPTED: no`, and the post-audit flow has resolved (one of: `SIGNUP_STATE` is `done` or `public-only`, OR `TOPIC_OFFERED: yes` for this repo).

> Help improve the Header skill? It can share **usage only** — which path ran, the outcome, and how many recommendations you applied. **Never** your code, file paths, repo names, or briefing content.
>
> 1. **Share usage** (recommended) — includes a random install id, not tied to your identity
> 2. **Anonymous only** — aggregate counts, no id
> 3. **No thanks**

```bash
<HEADER_BIN> set telemetry full        # "Share usage"   (or: anonymous / off)
touch "${HEADER_HOME:-$HOME/.header}/.telemetry-prompted"
```

Telemetry stays off until the user opts in here; they can change it any time with `header-config set telemetry off|anonymous|full`.

## What the audit scans

`bin/header-audit` is a deterministic, read-only scanner. The audit-led flow above calls it; this section documents the line types it emits so you can interpret them.

**Canonical ledger keys (`key=`).** Any line that can become a recommendation ends with a final tab field `key=<canonical-key>`, derived deterministically from the line's own fields — `gate-<eco>` on an absent `GATE`, `rail-<name>` on an absent `RAIL`, `delete-<pattern-id>` on a `HIT`, `trim-<file>` on `FILE`/`NESTED`, `migrate-`/`adopt-<model>` on `MODEL-STALE`/`MODEL-UPGRADE`, `route-<model>` on `ROUTE-CANDIDATE`, `waste-mcp-<server>`/`waste-skill-<name>` on the unused rows, `stale-ref-<ref>`, `bash-allowlist`, `hook-<event>-<cmd>`, `review-skill-<name>`, `error-rate-<tool>`, `skill-context-tax`. Evidence/context lines (`IMPORT`, `MODEL`, `SPEND`, `TOOL-USE`, `RAIL-ENV`, present/`n/a` `GATE` and `RAIL` rows, …) carry none. The flow uses an emitted key verbatim as the recommendation-ledger key — see "Recommendation ledger".

### `header-audit harness`

The premise — *"prompts are technical debt too"*: harness instructions are written for a model and a moment, and they rot silently (workarounds for weaknesses newer models fixed, format-nagging, role puffery, all loaded every turn). Output lines (tab-separated):

- `FILE <path> <bytes> <est_tokens>` — every always-loaded harness file found (`CLAUDE.md`, `AGENTS.md`, settings, commands, subagents, MCP config, editor rules). `est_tokens` is `bytes/4`. Sum these — that cost is paid on **every turn**.
- `IMPORT <parent> <imported-path>` — an `@import` edge. Claude Code (and AGENTS.md) load an `@path` line's target inline, every turn, so the auditor follows imports and emits the imported file as its own `FILE` row. **Include imported files in the always-loaded sum** — the previous scan undercounted by ignoring them.
- `NESTED <path> <bytes> <est_tokens>` — a subdir `CLAUDE.md`/`AGENTS.md`. Loaded **on demand** when the agent works in that subtree, *not* every turn — so count it apart from the always-loaded total (it still rots; flag debt the same way).
- `MODEL <value>` — the model the harness runs: declared in `.claude/settings.json`, else the most recent primary model in the user's transcripts (`~/.claude/projects`). So `MODEL` / `MODEL-STALE` / `MODEL-UPGRADE` fire even when the user pins nothing and rides the default alias.
- `MODEL-STALE <value> <why>` — the model id names a **superseded tier** (Claude 3.x/2.x/instant; early Opus 4.0/4.1). Pure hypothesis-generation: cross-reference the briefing for the current recommended tier and surface a model-migration `[Experiment]`. Conservative by design — current ids aren't flagged.
- `MODEL-UPGRADE <value> <recommended> <why>` — a newer model has shipped above the current engine, **priced honestly**: pre-4.8 Opus tiers get the *same-price* move (Opus 4.5/4.6/4.7 → Opus 4.8); Opus 4.8 gets the tier above (→ Fable 5, **2× token price** — the `<why>` says so). An **opportunity, not debt** (distinct from `MODEL-STALE`): offer the **engine-adoption card** (`/header fable-5` / `/header opus-4.8`, matching the recommended model) for the grounded case + caveats, then `header-experiment mine --adopt` to prove it on the repo. Conservative — never fires on the top tier (Fable 5) or a superseded tier.
- `HIT <path> <lineno> <pattern_id> <excerpt>` — a known cargo-cult pattern (built-in or briefing-supplied). Run `<AUDIT> patterns` to list the ids and why each is debt.
- `PROVEN <pattern_id> <effect> <n_repos> <ci>` — cross-customer library evidence for a pattern (from a 6-field `patterns.tsv` row). When a `HIT`'s pattern id has a `PROVEN` line, **cite it with the finding** — "proven: median <effect> across <n_repos> repos (CI <ci>)" — and treat the deletion as `[Apply with review]` with the library as the evidence. Don't scaffold a local experiment to re-prove a change the library already measured at scale; that's the whole point of pooling.
- `STALE-REF <path> <lineno> <ref> <why>` — the harness names a path/script or `@import`s a file that **doesn't exist** (moved, renamed, deleted). High-trust, low-risk: fix the reference or delete the dead instruction — usually `[Apply with review]`. (Deterministic and conservative — only path-shaped backtick tokens and unresolved imports; documentation placeholders like `path/to/x` are skipped.)
- `HOOK <event> <command-excerpt> <file>` — a shell command wired to an agent event (`PreToolUse`, `Stop`, …) in Claude Code settings. The **biggest unguarded execution + supply-chain surface**, and one the Bash-posture check is blind to (a hook runs regardless of the Bash allow/deny list). Surface any unexpected or opaque hook command as a security finding; an attacker who can write settings owns the agent.
- `SKILL <name> <path> <has-bin> <scope>` — an installed skill (`scope` = `repo` or `user`). Skills carry their own instructions and, when `has-bin yes`, executable scripts — a supply-chain surface (cf. `/cso`'s skill-supply-chain scan). Header is itself a skill, so this is dogfood-credible. Flag skills you don't recognize, especially user-scope ones with bin scripts.
- `SECURITY bash <level> <file>` (+ `SECURITY-DETAIL allow|deny <pattern>`) — Bash-tool permission posture from Claude Code settings:
  - `bypass` → **no permission gating** (`defaultMode: bypassPermissions`). Highest risk; if the agent can reach any production asset, recommend a command allow-list.
  - `denylist` → blacklist, which is bypassable (an agent can script around a blocked command) — recommend an allow-list.
  - `allowlist` → whitelist-leaning; affirm it, suggest tightening only if gaps.
  - **no `SECURITY` line** → no explicit policy (interactive prompts only). Fine for local dev; recommend an allow-list anywhere the agent reaches production.

Curate the hits — don't surface them blindly. When `MODEL` is known, cross-reference its model card / release notes to confirm the pattern is **still** debt on that model.

**Briefing-supplied patterns.** Beyond the built-ins, `header-audit` appends extra patterns from `${HEADER_HOME:-$HOME/.header}/patterns.tsv` (override with `HEADER_PATTERNS_FILE`): `id<TAB>regex<TAB>why` rows (hypotheses) or `id<TAB>regex<TAB>why<TAB>effect<TAB>n_repos<TAB>ci` rows (**proven** — the cross-customer library has measured the change), `#` comments and blanks ignored, anything that isn't exactly 3 or 6 tab fields skipped, ids de-duplicated (first wins, so built-ins keep their regex). Writing the briefing's named debt patterns there (Step 3) lets new hypotheses ship without a skill release; `<AUDIT> patterns` lists them — annotating proven ids with their library evidence — and notes the source file.

### `header-audit deps`

Output lines:

- `ECOSYSTEM <name> <manifest>` — detected ecosystems (npm is also detected one directory level deep, e.g. `frontend/package.json` in a monorepo).
- `TOOL <name> <version|-> <ok|too-old|absent>` — package-manager version vs. the minimum that honors a cooldown gate (npm ≥ 11.10, pip ≥ 26.1). Emitted only for detected ecosystems.
- `GATE <name> <present|absent|n/a> <path|->` — whether an install-cooldown / `min-release-age` configuration is in place. **`n/a` means the repo doesn't use that ecosystem — skip the row, exactly like the rails scan's `n/a`**; never recommend an npm/pip gate to a repo that installs through neither.

Surface:

- **Supply-chain cooldown.** `GATE npm absent` or `GATE pip absent` (never `n/a`) → recommend a `min-release-age` / `--uploaded-prior-to` gate so freshly-compromised releases (the chalk/debug, eslint-config-prettier class) are blocked until they're caught. This matters most where the install runs with secrets (CI runners). Get the exact snippet:

  ```bash
  <AUDIT> gate npm 7      # prints .npmrc content (min-release-age=7)
  <AUDIT> gate pip 7      # prints pip cooldown guidance (--uploaded-prior-to P7D)
  ```

  `TOOL npm too-old` / `TOOL pip too-old` → the gate is **silently ignored** until the tool is bumped locally **and in CI**.
- **Outdated / vulnerable deps.** Run the ecosystem's own tools (`npm outdated`, `npm audit`, `pip list --outdated`). Security patches → `[Apply now]`. Minor / patch upgrades with clean changelogs → `[Apply with review]` (one sanity replicate if you're nervous). Major upgrades where behavior may shift → `[Experiment]`.

### `header-audit cost`

Makes the audit **cost-aware** — it opens with where the tokens actually go. Defers all pricing to the sibling `header-cost` (single source of truth for the price table, cache-write split, and legacy-Opus handling); this scan just locates usage and reshapes `header-cost report --json` into audit rows.

**Scoped to the current repo by default.** It reads only *this* repo's transcript dir — `$HOME/.claude/projects/<repo-key>`, where `<repo-key>` is the absolute git-root path with every non-alphanumeric char replaced by `-` (Claude Code's own convention; e.g. `/Users/me/forge` → `…/projects/-Users-me-forge`). If that dir doesn't exist it emits a `NOTE` and stops — it **never** silently aggregates every project (that over-attribution is exactly what produced a misleading cross-repo recommendation; HEA-435). `--all-projects` opts into the machine-wide aggregate (clearly labeled `global`); `--input F` prices an explicit usage JSONL; `--since T` scopes the window; `--harness NAME` overrides harness detection. Output lines:

- `COST-SCOPE repo <repo>` — default: spend is this repo's transcripts only.
- `COST-SCOPE global <dir> <n> project dirs` — `--all-projects`: machine-wide aggregate. Background context only, never a per-repo recommendation.
- `COST-SCOPE input <path>` — `--input` was used.
- `COST-INPUT <dir> <n> files` — the repo-scoped transcript dir actually priced.
- `COST-HARNESS <harness> claude-transcripts` — whose usage this is. `header-cost` only parses Claude Code transcripts, so when `<harness>` is `codex` the spend is historical Claude usage, not the active engine.
- `COST-NOTE harness-mismatch <why>` — active harness is Codex over Claude data; downgrade the recommendation (see Step 4).
- `SPEND-TOTAL <usd> <calls> [<since>]` — total measured spend (API rates) over the window.
- `SPEND <model> <calls> <usd> <share_pct>` — one per model, sorted by cost; `share_pct` is its slice of the total.
- `ROUTE-CANDIDATE <model> <usd> <share_pct>` — the costliest model: the headline model-routing experiment candidate.
- `NOTE cost <reason>` — no usage history for this repo, or `header-cost` not found. Degrade gracefully: skip the spend lead, mention it in one line (and that `--all-projects` exists).

**Run the scope + harness sanity check before presenting any spend (Step 4).** Only when `COST-SCOPE` is `repo` and `COST-HARNESS` is `claude` should spend lead the scorecard and `ROUTE-CANDIDATE` become a ranked model-routing `[Experiment]`. A `global` scope or a Codex harness-mismatch is **background only**. When it does lead: surface the breakdown first (with `header-cost`'s price-source/freshness + billing-mode notes — see `reference/cost.md`), then convert `ROUTE-CANDIDATE` into the model-routing `[Experiment]`. It's a **candidate to prove, never a projected saving**: re-rating the same tokens on a cheaper model is a guess; the honest number comes from `header-experiment` (model-swap). This is the audit's most on-thesis upgrade — it grounds the model-migration hypothesis (the moat's first learning) in the user's real money.

### `header-audit waste`

Usage accounting over the same transcripts `cost` prices: what the harness **pays for vs what it uses**. Every row is deterministic evidence from the user's own sessions — no experiment needed, removing dead weight is the cleanest measured win. Scope discipline mirrors `cost` (this repo's transcripts by default; a missing dir is a `NOTE`; `--all-projects` is the explicit global opt-in; `--since T` windows it). Output lines:

- `WASTE-SCOPE` / `WASTE-INPUT` — same semantics as the cost scan's scope rows. Apply the same sanity check before presenting: a `global` scope is background context, never a per-repo recommendation.
- `TOOL-USE <tool> <calls> <errors>` — per-tool usage over the window, sorted by calls.
- `MCP-SERVER <server> <calls> <errors>` — rollup of `mcp__<server>__*` calls per server.
- `MCP-UNUSED <server> <config-file>` — configured in the repo's `.mcp.json`, **zero calls in the window**. Its tool schemas are loaded into context every turn for nothing — surface as `[Apply with review]`: remove the server entry (diff-faithful, trivially reversible). Ledger key `waste-mcp-<server>`.
- `SKILL-USE <name> <n>` / `SKILL-UNUSED <name> <path>` — Skill invocations seen vs **repo-installed** skills never invoked here (`[Apply with review]`, ledger `waste-skill-<name>`). User-scope skills are never flagged unused — they serve other repos — but still appear in the tax rows below.
- `ERROR-RATE <tool> <errors> <calls> <pct>` — a tool failing ≥20% of ≥10 calls. A hypothesis generator, not a verdict: look at *what* keeps failing (a broken hook, a misconfigured MCP server, a permission gap) and surface the likely fix.
- `COMPACTIONS <n> <files>` — context-pressure signal: the agent ran out of window <n> times across <files> session files.
- `SKILL-TAX <name> <scope> <bytes> <est_tokens>` / `CONTEXT-TAX skills <count> <bytes> <est_tokens>` — every installed skill's frontmatter (name + description) is loaded each session, used or not. The total belongs on the scorecard next to the always-loaded file sum; the per-skill rows name the heavy ones.

### header-audit rails

The **constructive** scan: where `harness`/`deps`/`cost` find debt to remove, `rails` finds guardrails to *add*. It detects whether the repo has the determinism rails that make AI-written code reliable, and reports the environment the delivery chooser needs. Read the line types here; the full pitch + install flow is in `reference/rails.md`. Output lines (tab-separated):

- `RAIL-ENV <key> <value>` — context for adapting + delivering the scaffold:
  - `ecosystem <python|npm|go|cargo|bundler|unknown>` — primary stack (precedence order), used to adapt the gate's checks. `ecosystem-all` lists every detected stack.
  - `git-remote <yes|no>` — a configured remote means a shared repo, so team propagation matters (favor the PreToolUse delivery, or both).
  - `hooks-path <value|unset>` — `core.hooksPath`.
  - `claude <yes|no>` — a `.claude/` dir; the PreToolUse delivery is only available when `yes`.
  - `tests <path|none>` — a detected test suite; `none` makes the ratchet `n/a`.
- `RAIL <name> <present|absent|n/a> <evidence>` — one per rail (`precommit-gate`, `test-ratchet`, `compound-memory`). Detection is deliberately conservative — a false *present* (re-nagging a repo that already has a gate) is worse than a false *absent*. `n/a` means the rail doesn't apply (e.g. a test ratchet with no test suite) — skip it, don't surface it.

**Scaffold printer (the `gate` analogue):**

```bash
<AUDIT> rail precommit-gate --ecosystem <eco> --delivery <git|pretooluse|both> [--ratchet on|off]
<AUDIT> rail test-ratchet                 # the standalone ratchet block, to insert into an existing gate
<AUDIT> rail compound-memory              # native /header wrapup pointer + a seed .claude/memory/MEMORY.md (standalone /compound skill optional)
```

Like `gate npm 7` prints the `.npmrc`, `rail <name>` prints the ready artifact — stack-adapted from the `header/scaffold/` templates, with the chosen delivery wiring appended. `precommit-gate` bundles the test ratchet by default (`--ratchet off` to omit); the correctness-critical bits (the `git commit` detector, the corrected skip/xfail regex) travel verbatim in the template. An unknown ecosystem still prints a usable gate with a `TODO` checks block. The SKILL.md flow writes the files; the bin only prints.

### `header-audit retro`

The **coach** scan: behavioral mining of the user's OWN sessions — the signals the accounting scans (`cost`/`waste`) don't surface. Same repo-scope discipline (this repo's transcript dir by default; a missing dir is a `NOTE`; `--all-projects` is the global opt-in; `--since T` windows it; `--input F` reads an explicit JSONL). Read-only; nothing leaves. Output lines:

- `RETRO-SCOPE` / `RETRO-INPUT` — same scope semantics as `cost`/`waste`; a `global` scope is background, never a per-repo claim.
- `RETRO-WINDOW <n_sessions> [<since>]` — sessions in the window. `RETRO-HARNESS claude-transcripts` — the harness these read (see the harness note in the coach lead).
- `RETRO-SHIP <commits> <loc+> <loc->` + `RETRO-PEAK <day> <commits>` — git activity over the window (repo scope, git repo only): the overview's "what shipped" + busiest day.
- `RETRO-PLAN <n_planned> <n_sessions>` — sessions that opened plan mode → a low rate nudges plan-first. `RETRO-CORRECTION <n>` — user redirects → `feedback_` candidates for compound.
- `RETRO-CORR plan-mode <avg_err_planned> <avg_err_unplanned>` — per-session correlation: avg Bash errors in plan vs no-plan sessions (emitted only with ≥2 of each). When `planned < unplanned`, it *quantifies* the plan-first nudge ("planned 0.2 vs 1.1 errors").
- `RETRO-GAP <n_sessions> <total> key=cap-verify` — sessions with an edit + a "fixed/done" claim but **no test run** = a verification gap → a `pitfall` for compound; the `precommit-gate` rail addresses it.
- `RETRO-THRASH <file> <edits>` — a file re-edited ≥5 times: a rework signal (the agent not landing it first pass), sorted desc. Heavy thrash on one file alongside a heavy always-loaded `FILE` + non-zero `COMPACTIONS` is the practical argument to split it.
- `RETRO-FAILS <tool> <errors> <calls>` — failed-tool volume. **Bash errors are the gotcha/pitfall signal** — the count is precise (error attribution), but the *narrative* (what actually broke) you read from your own session context (a wrapup) or the recent transcript. 0 errors → a clean week; say so, don't invent gotchas to fill the section.
- `RETRO-GIT <pattern> <count>` — git-workflow tells (`stash`, `branch-switch`, `worktree`, `reset-hard`, `force-push`). **Interpret, don't verdict** (à la `ERROR-RATE`): counts include git strings that appear in tool inputs (test fixtures, examples), so treat `reset-hard`/`force-push` as soft signals. The CAP derivations below key only off `stash`/`branch-switch`/`worktree` and precise error attribution.
- `RETRO-CAP <capability> <evidence> key=cap-<capability>` — the **derived** behavior→practice nudges, the ranked spine of the coach lead. Three, each emitted only when its threshold is met:
  - `worktree` — ≥3 branch-juggling events (stash/switch) and **no** worktree use → recommend git worktrees.
  - `guardrail` — ≥3 failed Bash calls → recommend the `precommit-gate` rail (cross-check `RAIL precommit-gate`; **affirm** it if already present).
  - `compound` — ≥3 gotchas **and** no committed `.claude/memory/` → recommend `/header wrapup`.
  Render only the caps that fired, in emission order (= order of demonstrated need). Each carries `key=cap-<name>` — use it verbatim in the ledger. A weak cap (low count) → rank it low and **say it's weak**; never hard-sell (the anti-upsell discipline that the engine-adoption upsell got wrong).

### `header-audit grade`

The **composite setup grade** — one glanceable mark (e.g. `B+`) summarizing the five scorecard axes, so the report can answer "how's my setup?" before the detail. Re-runs `harness` + `deps` + `rails` internally (cheap, read-only) and reduces their findings to a single letter. **Static-config only:** the transcript-mined scans (`cost` / `waste` / `retro`) are excluded, so the grade is stable whether or not the repo has session history — and identical run-to-run, model-to-model, because it is **computed in the bin, never model-assigned**. Output lines:

- `GRADE-AXIS <axis> <delta> <note>` — the per-axis deduction (five rows, fixed order: `context` / `model` / `security` / `deps` / `rails`); `delta` is `-N` or `0`, with a one-clause reason. The breakdown behind the letter — surface it only if the user asks "why that grade?".
- `GRADE <letter> <score> 100` — the composite (start 100, deduct per finding, clamp 0–100), mapped to a standard `+`/`-` band (`A+` … `F`). Render the **letter only** as the scorecard headline — drop the `<score>` (see the contract above); the score stays in the line for the breakdown + tests, not the user-facing render.

**What it weighs** (a stability contract — the same inputs always yield the same grade, so the bands/weights don't drift between runs): always-loaded context tokens (tiered) + prompt-debt `HIT`s + `STALE-REF`s · a `MODEL-STALE` superseded tier (a `MODEL-UPGRADE` *opportunity* is **not** penalized — being on a current tier never costs points) · a weak Bash posture (`bypass` / `denylist`; "no explicit policy" is fine for local dev and doesn't deduct) · absent supply-chain cooldown gates · absent determinism rails (weighed **light** — opinionated house guardrails, not measured on your repo). A clean, current, lean setup lands at `A`/`A+`; debt and risk pull it down. Package-tool versions (`TOOL too-old`) are a scorecard note, **not** a graded axis — grading them would make the mark machine-dependent.

### Record findings

Each finding becomes a ledger entry, as documented in the recommendation ledger above. Telemetry aggregates demand consent-gated — **never** sends code, paths, or line content; only counts and kinds.

## Cost analytics (`header-cost`) — beta

Direct `header-cost` usage — the audit-led spend path already lives in the flow above. **→ `reference/cost.md`.**

## Determinism rails (guardrails) — beta

The constructive *add-a-guardrail* axis (pre-commit gate / test ratchet). Detection runs in `<AUDIT> rails`; the pitch, delivery chooser, and install flow → **`reference/rails.md`.**

## Session wrap-up & compound (`/header wrapup`, `/header compound`)

> **Beta — Header's compounding-memory motion, run natively.** Header *does* the
> capture instead of recommending you go install a separate `/compound` skill.
> The canonical process is `scaffold/compound/SKILL.md`; this section is that
> process, executed by the skill. No audit runs in this flow.

**What each is for.**
- **`/header compound`** — *capture only*. Run it anytime: mid-session right after
  something breaks, a workaround lands, the user corrects you, or an approach
  works notably well; or at the end. Straight to capture, no recap.
- **`/header wrapup`** — the **session-end ritual**: a 2–4 line recap of what the
  session actually did, then the same capture. (This is the seed of the fuller
  "coach" retro; today it is recap + capture.)

Both write to the repo's committed `.claude/memory/`, so a captured pitfall is
one a *future* session — yours or a teammate's — won't re-hit. This is the
compounding flywheel, adjacent to Header's own recommendation ledger.

### The flow (pinned)

1. **(`wrapup` only) Recap.** From your own session context, render 2–4 plain-
   language lines: what the user set out to do, what actually shipped/changed,
   and any notable rough patch. Then continue to capture.

2. **Review the session for learnings.** Source is your own conversation context
   — you lived this session. *(Run in a fresh session with no relevant context?
   Fall back to the repo's most recent transcript under
   `~/.claude/projects/<repo-key>/`.)* Pull **at most 3**, each in exactly one
   category (the filename prefix):
   - `feedback_` — a user correction or stated preference.
   - `pattern_` — an approach that worked and should be repeated.
   - `pitfall_` — something that broke, failed, or wasted time.
   - `domain_` — a project fact discovered during the work.
   Most sessions yield **0–2. Do not force it.** Nothing notable → print
   `Compound: reviewed, nothing notable to capture` and stop. The review itself
   is the work product. **Do not capture:** task status/progress, implementation
   detail (→ code comments), anything already in `CLAUDE.md`/`AGENTS.md`, or
   one-off debugging that won't recur.

3. **Locate / seed the store.** Memory lives in `.claude/memory/` (committed). If
   `.claude/memory/MEMORY.md` doesn't exist, seed it first (via Bash) with this
   skeleton — it mirrors `scaffold/compound/MEMORY.md`:
   ```
   # Memory Index

   Committed, compounding memory for this repo. Future sessions read this first.
   Each entry is one file under `.claude/memory/`; `/header compound` adds them.

   ## Feedback
   ## Patterns
   ## Pitfalls
   ## Domain
   ```

4. **De-duplicate.** Read the existing `.claude/memory/MEMORY.md` + entry files.
   A learning on the same topic as an existing entry → **update that file**, don't
   create a near-duplicate.

5. **Draft (don't write yet).** For each kept learning, draft a file at
   `.claude/memory/{prefix}_{slug}.md` (`{slug}` = kebab-case of the topic, e.g.
   `pitfall_git-from-repo-root.md`), 3–8 line body, in this **pinned** format:
   ```markdown
   ---
   name: <short imperative name>
   description: <one actionable line — starts with a verb or Never/Always; becomes the MEMORY.md index line>
   type: feedback | pattern | pitfall | domain
   date: <YYYY-MM-DD, from `date +%F`>
   ---

   <the learning, stated plainly>

   **Context:** <when/why it matters — cite the moment it came from>
   **Apply when:** <the specific condition a future session should recall this under>
   ```

6. **Draft-then-ask** *(locked: always ask before writing — a `header-config`
   "just write, don't ask" opt-in comes later)*. Show a compact summary — one
   bullet per draft, `{prefix}_{slug} — description` — then the line *"These live
   in `.claude/memory/` (committed → teammates read them next session)."* Then
   exactly **one** `AskUserQuestion`:
   - **Question:** "Capture these N learning(s) to `.claude/memory/`?"
   - **Options** (single-select; mark the **team** option *Recommended* when the
     repo has a git remote, else the just-me option):
     1. **Write + stage (team)** — write the files, `git add` them (committed
        memory travels to teammates).
     2. **Write, uncommitted (just me)** — write the files, no `git add`.
     3. **Show me the full files first** — render the full drafts, then re-ask.
     4. **Skip** — don't write; print `Compound: reviewed, chose not to capture`.
   "Skip" ≠ "wrong" — the user may want them local-only, or not now.

7. **Write + index** (Bash — the skill's only write path). For each confirmed
   file: write it, then add its line `- [{prefix}_{slug}.md]({prefix}_{slug}.md) —
   <description>` under the matching `## Section` in `.claude/memory/MEMORY.md`. If
   the user chose **team**, `git add` the written files — do **not** commit unless
   they ask. Close with one line: `Compound: captured N learning(s) — <slugs>`.

### When the audit sends you here

The `compound-memory` rail (when `absent`) points at this flow: the audit
recommends running `/header wrapup` at session end rather than installing a
separate skill. If the user takes it, seed `.claude/memory/MEMORY.md` (step 3) so
the store is ready for the first capture.

## Engine-adoption card (`/header fable-5`)

`/header fable-5` / `/header opus-4.8` — the grounded "should you move to this model?" card. **→ `reference/engine-adoption.md`.**

## Experiments (`header-experiment`) — beta

The local A/B engine (`header-experiment`): mine tasks from git history, run model/effort sweeps, prove a change before trusting it. **Full CLI + flow → `reference/experiments.md`.**

## Browse public topics

**→ `reference/custom-briefings.md`.**

## Custom briefings (API key required)

Authenticated workflows: custom topics, sources, schedule, team config. **→ `reference/custom-briefings.md`.**

## Error handling (every Header API call)

Don't auto-retry blindly; inform the user before retrying.

| Condition | Action |
|---|---|
| Network failure / DNS / timeout | `--retry 1` handles transient blips. Second failure → tell the user the API is unreachable, stop. |
| HTTP `429` Too Many Requests | Read `Retry-After`. Wait that many seconds (or 30s if absent), retry once. If still 429, stop. |
| HTTP `4xx` (other) | Surface JSON `detail` or `error.message`. Don't retry. |
| HTTP `5xx` | Retry once after 5s. If it fails again, tell the user. |
| Empty body / malformed JSON | Tell the user; suggest the catalog fallback. |
| Briefing `status: FAILED` | Don't auto-retry. Suggest re-triggering via `POST /api/v2/goals/{goal_id}/briefings`. |

## Response Reference

API response shapes (BriefingResponse, etc.). **→ `reference/custom-briefings.md`.**

