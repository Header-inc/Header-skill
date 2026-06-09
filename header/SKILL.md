---
name: header
version: 0.24.2
description: "Audit and optimize the AI coding agent's own setup — CLAUDE.md, model choice, dependencies, settings — for prompt-config debt and supply-chain risk. Each invocation runs the audit, enriched by the latest agentic-coding briefing relevant to your stack. Public access needs no auth; authenticated workflows use an API key."
when_to_use: "Use to audit and improve the agent's own setup. Triggers include audit, audit my setup/agent/harness, optimize codebase, reduce token cost, supply-chain risk, dependency upgrade, CLAUDE.md or prompt debt, add a pre-commit hook / guardrails / determinism rails, test ratchet, compounding memory / capture learnings, latest best practices, what's new in agents/MCP/coding tools. Runs on /header, /header-audit, or the legacy /header-briefing. Pass a topic name, UUID, or briefing URL to swap the enrichment topic; otherwise the default agentic-coding topic is used. Run '/header opus-4.8' (or 'adopt') for the engine-adoption card — a grounded 'should you move your harness to Opus 4.8 / a newer model?' answer that hands off to a model+effort experiment (header-experiment mine --adopt)."
argument-hint: "[topic-name-or-uuid-or-briefing-url]"
allowed-tools: Bash, AskUserQuestion
---

*The `when_to_use`, `argument-hint`, and `allowed-tools` frontmatter fields are honored by Claude Code; other harnesses ignore them safely.*

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
| `TEAM_CONFIG` | Path to the committed `<repo>/.header/config` (the team layer), or `none`. A path means this repo ships shared Header settings — see "Team config". |
| `TEAM_TOPIC` | Topic UUID pinned by the committed team config, or empty. When non-empty **and** a key is available it sits above `DEFAULT_TOPIC` but below a personal `REPO_TOPIC` binding in topic resolution. |
| `DEFAULT_TOPIC` | Personal/global topic UUID — env var → `~/.header/config` → empty. Used when no argument, personal binding, or team topic applies. |
| `REPO_TOPIC` | Topic UUID this repository is **personally** bound to (via `header-repo`), or empty. When non-empty **and** a key is available, it wins over `TEAM_TOPIC` and `DEFAULT_TOPIC`. |
| `LANGUAGE` | Render user-facing output in this language. Resolves env → team config → personal config → `English`. |
| `STALENESS_DAYS` | Threshold for the briefing-age check. Resolves env → team config → personal config → `7`. |
| `INTERACTIVE` | `no` → scheduled / non-interactive run: skip every prompt. `yes` → all prompts are eligible. |
| `WELCOME_SEEN` | `no` (with `INTERACTIVE: yes`) → show the first-run welcome before the audit. |
| `LANGUAGE_PROMPTED` | `no` (with `INTERACTIVE: yes` and `LANGUAGE: English`) → show the first-run language prompt. |
| `SIGNUP_STATE` / `HAS_KEY` | Drive the post-audit custom-topic offer — see "After the audit: customize your topic". |
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

> **Mode routing:** the audit always runs. A short word at the end of the invocation switches **what gets shown**, not what gets done: `summary` → render only the briefing's `summary` field, no audit output; `sources` → only `source_articles`, no audit output; `add-source <url>` → see "Add a source"; `since-last` → see "Since-last digest"; `cost` → see "Cost analytics". One argument is special-cased to a *different* flow: `opus-4.8` (also `opus-4-8`, `adopt`) → render the **engine-adoption card** (see "Engine-adoption card (`/header opus-4.8`)"), a self-contained "should you move your harness to this model?" answer — not a topic. Anything else (a topic name/UUID/briefing URL, or no argument) runs the full audit-led flow below.

### Step 0 — Resolve the topic

The topic determines which briefing is pulled in for enrichment. Fallback chain (first match wins):

> **Engine-adoption short-circuit:** if the argument is `opus-4.8` / `opus-4-8` / `adopt` (or a `<model>-adoption` keyword), this is **not a topic** — render the **engine-adoption card** (see that section) and skip Steps 1–4. The card reads a bundled snapshot + the user's detected engine, not a briefing.

1. **Explicit argument** — if the user passed an identifier:
   - URL containing `/briefings/<uuid>` → extract the UUID, treat as a **briefing ID**, skip Step 1, go straight to Step 2 with `/api/v2/public/briefings/<uuid>`.
   - URL containing `/topics/<uuid>` or a bare UUID → use as the **topic ID** and proceed to Step 1.
   - Anything else → search `/api/v2/topics/public/catalog` for a case-insensitive substring match on `name`. One match → use its `id`; multiple → ask to disambiguate; none → fall through.
2. **Personal binding for this repo** — if `REPO_TOPIC` is non-empty **and** `HAS_KEY: yes`, use it (it wins over `TEAM_TOPIC`). Bound topics are private — use the authenticated endpoints, and run the session-start freshness check (see "Bound repos — freshness & schedule"). If `REPO_TOPIC` is set but no key is available, skip and fall through. A `404` means the topic was deleted server-side — offer `header-repo clear` and fall through.
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

From the JSON, pull `summary`, `key_developments`, `source_articles` (title + url), and `generated_at`. `key_developments` is a JSON-encoded string — parse it into a structured list.

**Staleness:** compare `generated_at` to today. If older than `${HEADER_STALENESS_DAYS:-7}` days, prepend a one-line warning to the audit output. With an API key, suggest re-triggering generation via `POST /api/v2/goals/{goal_id}/briefings`.

**Merging the default briefings (two-topic default only).** When you fetched both public topics, pull `summary` / `key_developments` / `source_articles` / `generated_at` from each, then combine: concatenate `key_developments` and `source_articles` across both briefings and **de-duplicate** near-identical items (same headline, or same source URL), keeping one. When the origin matters, label a surfaced item with its topic (*Self Improving Agent* / *Agentic Coding*). Apply the staleness check **per briefing** — warn if **either** is older than `${HEADER_STALENESS_DAYS:-7}` days, naming which. For the `summary` / `sources` output modes on the two-topic default, show **both** (each labeled by topic). A single resolved topic (Steps 1–4) is unchanged: one briefing, no merge.

### Step 3 — Run the audit

Local, read-only — nothing leaves the machine. Run **all five** scans. `<AUDIT>` is `header-audit`, in the same `bin/` dir as the preamble's `HEADER_BIN`.

```bash
<AUDIT> harness          # CLAUDE.md / AGENTS.md (+ @imports) / settings / hooks / skills / commands / subagents / MCP / Bash posture / model staleness / stale refs
<AUDIT> deps             # ecosystems / tool versions / install-cooldown gate
<AUDIT> cost             # spend-by-model from your real transcripts → top model-routing candidate
<AUDIT> waste            # usage accounting from the same transcripts: unused MCP servers / skills, tool error rates, compaction pressure, skill context tax
<AUDIT> rails            # determinism guardrails present|absent (pre-commit gate / test ratchet / compounding memory) — opinionated, additive
```

**Briefing-supplied patterns (run before `harness`).** The 8 prompt-debt patterns are built in, but the briefing can ship new ones without a skill release. If the fetched briefing names additional cargo-cult / debt phrases (a `debt_patterns` field, or patterns called out in `key_developments`), write them to `${HEADER_HOME:-$HOME/.header}/patterns.tsv` *before* running `harness` — one `id<TAB>regex<TAB>why` per line — and the scan picks them up as `HIT`s with your ids. **Proven rows:** when the briefing carries cross-customer evidence for a pattern (a measured effect from the proven-changes library), write a 6-field row instead — `id<TAB>regex<TAB>why<TAB>effect<TAB>n_repos<TAB>ci` — and `harness` re-emits the evidence as a `PROVEN` line (a proven row may reuse a built-in id to attach evidence to it; the scan de-duplicates by id, first wins). Keep regexes conservative (`grep -iE`); malformed lines (not exactly 3 or 6 tab fields, or a non-integer `n_repos`) are skipped. This is how the distribution wedge feeds new hypotheses — and proven library results — into the deterministic scanner.

What the scans emit — and how to read each line — is documented under **"What the audit scans"** below. Capture the output and the line types (`FILE`, `IMPORT`, `NESTED`, `MODEL`, `MODEL-STALE`, `MODEL-UPGRADE`, `HIT`, `STALE-REF`, `HOOK`, `SKILL`, `SECURITY`, `ECOSYSTEM`, `TOOL`, `GATE`, `COST-SCOPE`, `COST-INPUT`, `COST-HARNESS`, `COST-NOTE`, `SPEND`, `ROUTE-CANDIDATE`, `WASTE-SCOPE`, `WASTE-INPUT`, `TOOL-USE`, `MCP-SERVER`, `MCP-UNUSED`, `SKILL-USE`, `SKILL-UNUSED`, `ERROR-RATE`, `COMPACTIONS`, `SKILL-TAX`, `CONTEXT-TAX`); you'll join them with the briefing in the next step.

### Step 4 — Cross-reference and present

The audit's findings + the briefing's items become **one ranked recommendation list**.

**Recent activity (diff-aware):** glance at recently-touched files (`git log --name-only --pretty=format: -15 2>/dev/null | sort -u`) and recent commit subjects (`git log --oneline -15 2>/dev/null`). Weight recommendations toward areas with recent activity — a briefing item or audit hit that touches code the user changed this week is more actionable than one about a dormant corner. Name the connection when you surface it.

**Open with the money — but only spend that matches this repo and harness.** Before leading with any `SPEND` row, run the **scope + harness sanity check**: *does this spend source match the current repo and the current agent harness?* Read it off the markers `<AUDIT> cost` emits:

- **`COST-SCOPE repo`** + `COST-INPUT` → the spend is this repo's own transcripts. Safe to lead with and to turn into a ranked recommendation. (The default; nothing else aggregates silently.)
- **`COST-SCOPE global`** (only ever from an explicit `--all-projects`) → machine-wide spend across *all* projects. Present it as **background context only** — "across all your projects you've spent ~$X" — **never** as a ranked recommendation for *this* repo. Don't promote its `ROUTE-CANDIDATE` to an `[Experiment]`.
- **`COST-HARNESS codex …`** with a **`COST-NOTE harness-mismatch`** → the priced transcripts are *historical Claude Code* usage; the active harness is Codex, so this spend does **not** measure your current engine. Do **not** surface `ROUTE-CANDIDATE` as a model-routing `[Experiment]`. Say instead: *"No Codex cost data available; run a Codex 5.x paired experiment if you want to test model choice."* If you do mention the figures, label them explicitly as historical Claude Code usage only.

When the source *does* match (repo-scoped, harness `claude`), *lead* the scorecard with where the tokens actually go — "this period you spent ~$X; N% of it on `<top model>`" — using the `SPEND-TOTAL` / `SPEND` lines (always surface `header-cost`'s price-source + freshness line and the billing-mode note; see "Cost analytics"). Then turn the `ROUTE-CANDIDATE` (the costliest model) into the headline **model-routing `[Experiment]`**: "route the low-stakes share of this spend to a cheaper tier — prove it before trusting the saving." This is the on-thesis hypothesis (model migration is the moat's first learning); it's a *candidate to prove*, never a projected saving — drive it with `header-experiment new --kind model-swap` (see "Experiments"). If `cost` returned only a `NOTE` (no usage history for this repo yet), skip the spend lead and say so in one line — mention `--all-projects` is available for machine-wide spend.

Build the unified list by combining:

- **Audit findings** — every `HIT` (prompt-debt pattern, built-in *or* briefing-supplied; when the pattern id carries a `PROVEN` line, cite the library evidence and skip the local experiment), `FILE` size signal (heavy always-loaded `CLAUDE.md`/`AGENTS.md` — **sum `FILE` + `IMPORT`ed files**, since @imports are loaded every turn too; `NESTED` files are on-demand, count them apart), `MODEL` mismatch / `MODEL-STALE` (pinned to a superseded tier → model-migration `[Experiment]`), `MODEL-UPGRADE` (a newer same-family model shipped, e.g. Opus 4.8 → offer the **engine-adoption card** (`/header opus-4.8`) and `header-experiment mine --adopt` to prove it — opportunity, not debt), `SECURITY` posture, `HOOK` (arbitrary shell on agent events — the biggest unguarded execution + supply-chain surface; treat an unexpected/opaque hook command as a security finding), `SKILL` (installed skills are a supply-chain surface — note any carrying `has-bin yes`, à la `/cso`), `STALE-REF` (a referenced path/script or @import that no longer exists), and `GATE absent` from `header-audit`.
- **Consistency findings** — `STALE-REF` lines are the deterministic half: surface each as `[Apply with review]` (fix the reference or delete the dead instruction). The other half is yours to judge — while reading `CLAUDE.md`/`AGENTS.md`, flag **mutually contradictory instructions** the greps can't catch (e.g. "use tabs" *and* "use spaces" for the same files; "always delegate to a subagent" *and* "never spawn subagents"; a rule that names a flag/command the tool no longer has). High-signal, low-risk — usually `[Apply now]` / `[Apply with review]`.
- **Briefing-derived recommendations** — items in the briefing's `key_developments` or `summary` that touch the project's stack/tooling (read package manifests, lockfiles, language version files, build/test/CI configs, container/infra definitions, agent/skill definitions, `CLAUDE.md`, README), or that name a pattern the project doesn't yet use (or uses a now-legacy version of). The bias is toward **deletion** and toward changes the briefing endorses on the model currently configured. For a `MODEL-STALE` hit, cross-reference the briefing for the *current* recommended tier — the bin flags that it's stale; the briefing names what to move to.
- **Waste findings** — the highest-trust deterministic wins in the audit, because each is *measured from the user's own sessions* (see "`header-audit waste`"). `MCP-UNUSED` and repo-scope `SKILL-UNUSED` → `[Apply with review]` removals, stating the evidence window ("0 calls across N session files"); an unused MCP server's tool schemas are paid for on **every turn**, so this routinely outweighs any single prompt-debt `HIT`. `ERROR-RATE` rows are investigate-hypotheses (what keeps failing, and why). A non-zero `COMPACTIONS` count alongside a heavy always-loaded `FILE`+`IMPORT` sum is the strongest practical argument for the trim recommendations — name the connection. Put `CONTEXT-TAX` on the scorecard next to the always-loaded sum. Ledger keys: `waste-mcp-<server>`, `waste-skill-<name>`.
- **Determinism-rail findings** — each `RAIL absent` from `<AUDIT> rails` is an *opportunity to add a guardrail* (a pre-commit quality gate, a test ratchet, a compounding-memory discipline). These are the audit's **constructive** axis — see "Determinism rails (guardrails)". Surface each as **`[Apply with review]` tagged `(opinionated — Header house guardrail, not measured on your repo)`**: the new hook/skill file *is* the diff-faithful change, but the justification is conviction, not an A/B. Honor the ledger (keys `rail-precommit-gate` / `rail-test-ratchet` / `rail-compound-memory`); **skip `n/a` rows** (e.g. a test ratchet on a repo with no tests). This does **not** contradict the `HOOK`-as-risk framing: a rail is committed, reviewable, from Header's documented template, and agent-actionable — the opposite of an opaque hook. (Once installed it will appear as a `HOOK` on the next `harness` scan — recognize it as the rail you just added, don't re-flag it.)
- **Known issues** — themes from learnings/post-mortems/runbooks/architecture-decision-records/incident reports + a quick `TODO`/`FIXME`/`HACK` density scan. A recommendation that addresses a known issue jumps the queue.

When a `MODEL` is known, cross-reference its model card / release notes before declaring a prompt-debt `HIT` actionable — confirm the pattern is *still* debt on that model. Prefer briefing sources for the cross-reference; fall back to the web.

**Present** as a one-line scorecard, then a ranked recommendation list. Each recommendation is a hypothesis: **what** (the change), **where** (file + line/manifest), **why** (cite the audit line *or* the briefing item — link the `source_articles` URL for the latter), and the **expected effect** (`est.` and directional unless measured). Sort findings into three buckets — the audit is not just a hypothesis generator, it's also a hypothesis *filter*:

- **`[Apply now]`** — strictly deterministic, low-risk: supply-chain gate, security patches, obvious bug fixes, doc typos. On the user's yes, make the edit (show a diff first; for the gate, write/append the `<AUDIT> gate ...` snippet to `.npmrc`). No verification beyond the diff.
- **`[Apply with review]`** — small-magnitude changes whose effect is observable from the diff alone: deletions of cargo-cult phrases (`as an AI language model`, `take a deep breath`, role puffery), trimming redundant role/persona boilerplate, doc cleanups, minor lint-style edits in CLAUDE.md / AGENTS.md. The user is the verifier — show the diff, get approval, apply. Optionally, run **one sanity replicate** (`header-experiment new --kind ... && header-experiment run <id> --k 1`) to confirm tests still pass; skip the full bootstrap A/B — the diff is the proof.
- **`[Experiment]`** _(beta)_ — only when the payoff is BOTH non-deterministic AND has enough magnitude to justify the experiment's own spend. Model swaps, subagent delegation toggles, fast-mode-instruction toggles, mandatory-skill rules, major framework migrations, behavior rewrites. If the user says "let's test that", **scaffold the spec from the finding payload** with `header-experiment new --kind ...` (see "Experiments" section below) — don't make the user retype what the audit already told us. The standard ledger dispositions apply per finding: `dismissed` if they reject this specific experiment, `wanted` if they want this one but aren't running it locally right now, `snoozed` for "not now."

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

After presenting, ask which (if any) to implement. On selection, proceed with the implementation in the current project.

**Commit signature.** When you (or the user) commit a fix that came from a recommendation the audit just surfaced, append a trailer to the commit message so the change's provenance is visible in `git log` / `git blame`:

```
Header-Audit-Finding: <ledger-key> — https://joinheader.com
```

Use the same `<ledger-key>` you logged to the recommendation ledger (e.g. `mcp-streaming`, `gate-npm`, `delete-think-step-by-step`). Multiple findings landed in one commit → emit multiple `Header-Audit-Finding:` lines, one per key. Skip the trailer when the user is making unrelated commits in the same session; this trailer is for changes that originated from a specific Header audit finding. If the user is committing manually rather than asking you to commit, show them the trailer line and let them decide whether to include it.

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
- Give each a short stable `key` (lowercase, hyphenated, e.g. `mcp-streaming`).
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

Once the audit + recommendations are delivered, in interactive mode, offer to **tailor the enrichment topic to this repo**. This is the upsell — the briefing that enriched the audit came from a generic topic; a custom topic targets sources about *your* stack.

**Conditions to fire** (all must hold):

- `INTERACTIVE: yes`
- `TOPIC_OFFERED: no` for this repo
- `SIGNUP_STATE` is **not** `public-only` (back-compat — honors older opt-out markers from 0.10.0/0.10.1; this skill no longer writes new ones)
- `REPO_TOPIC` is empty (this repo isn't already bound to a custom topic)

If any of those fails, skip this section and go straight to "Telemetry consent".

Ask (`AskUserQuestion` on Claude Code; numbered plain text elsewhere):

> The recommendations above were enriched by Header's **general** agentic-coding briefing — the same source feed for everyone. A **custom topic** would tune the enrichment to *this* repo: sources and focus tailored to your stack, so every future audit pulls in items directly relevant to your code.
>
> Want one for this repo?
>
> 1. **Yes — customize for this repo** (recommended for repos you'll work in repeatedly)
> 2. Remind me next session
> 3. Not for this repo — don't ask again

There is **no global "never ask anywhere" opt-out** — declines are per-repo only. Each repo is its own decision; "not for this repo" silences only here. (`<REPO>` is `header-repo`, next to the preamble's `HEADER_BIN`.)

### 1 — Yes, customize

If `HAS_KEY: no`, walk through signup first:

> Custom topics need a Header account. About 30 seconds, no card.
>
> Sign up at https://joinheader.com/ — start the free trial → open **Settings ▸ API Keys** → create a key with **read + write** access (`hdr_sk_...`; write is required to create custom topics) → paste it here.

Offer to open the URL:

```bash
URL="https://joinheader.com/"
if   command -v open     >/dev/null 2>&1; then open "$URL"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
elif command -v start    >/dev/null 2>&1; then start "$URL"
else echo "Open $URL in your browser."
fi
```

When the user pastes a key, offer to save it under a tight umask:

> Save it to `~/.header/credentials` (readable only by you) so you don't re-enter it each session?

Replace `PASTED_KEY` with the key the user pasted:

```bash
_HH="${HEADER_HOME:-$HOME/.header}"; mkdir -p "$_HH"
( umask 077; printf 'HEADER_API_KEY=%s\n' "PASTED_KEY" > "$_HH/credentials" )
chmod 600 "$_HH/credentials" 2>/dev/null
case "$(ls -l "$_HH/credentials" 2>/dev/null)" in
  -rw-------*) printf 'done\n' > "$_HH/.signup-state"; echo "Saved — custom briefings are ready." ;;
  *) rm -f "$_HH/credentials"
     echo "Could not secure the file — not saving the key. Add this to your shell profile instead:"
     echo "  export HEADER_API_KEY=PASTED_KEY" ;;
esac
```

If the user defers (won't paste a key right now), record `pending` and skip the rest — next run will re-offer once:

```bash
printf 'pending\n' > "${HEADER_HOME:-$HOME/.header}/.signup-state"
```

The credentials file is **only ever read as data** (parsed via `grep`/`sed`); nothing sources or executes it.

**With a key now available**, build the custom topic — the Step 3 audit already inferred the stack, so draft the goal for them. For a sharper fit, first let Header propose sources: `POST /api/v2/sources/recommend` → `POST /api/v2/sources/recommend/commit` returns a `group_id`. Then create the topic (see "Create a custom topic"); the response includes `first_briefing_id` — generation runs **asynchronously**, typically a few minutes.

> Creating a topic focused on <one-line summary of the detected stack and priorities>. The first briefing is generating in the background (~3-5 min); while we wait, let me get a couple of things set up.

**During the server-side generation**, run the chained per-repo offers — fill the dead air with the questions that depend on the new topic existing. Order:

1. **Bind the topic to this repo.** `"<REPO>" bind <new_topic_id> "<topic name>"` — future runs here use it automatically as `REPO_TOPIC`.

2. **Offer a schedule** (if `SCHEDULE_OFFERED: no`):

   > Keep this repo's briefing fresh automatically? Header regenerates it server-side on cadence, so a new one is waiting next session.
   >
   > 1. Every 3 days  2. Every 7 days (recommended)  3. Every 14 days  4. Every 30 days  5. No thanks

   On a cadence → `PUT /api/v2/goals/{default_goal_id}` with `schedule_enabled: true`, `schedule_frequency_days: N` (see "Bound repos — freshness & schedule"). Confirm and `"<REPO>" flag schedule-offered set` regardless.

3. **Offer team config** (if `TEAM_CONFIG: none`, `TEAM_CONFIG_OFFERED: no`, and a `git remote` is configured — i.e., shared repo):

   > Share this topic with your team? I can drop a `.header/config` in the repo pinning this topic — commit it, and every teammate's `/header` uses it automatically with no setup. (Recommended for shared repos.)

   On yes → `"<HEADER_BIN>" team-init <new_topic_id>` writes `./.header/config`; surface the `git add` hint so the file reaches teammates. Always `"<REPO>" flag team-config-offered set`. See "Team config" for what keys are allowed.

4. **Poll for the first briefing.** When all offers are resolved, check briefing status (see "Polling IN_PROGRESS briefings"). When `COMPLETED`, surface one line — "✓ Your custom briefing is ready; next session here will use it" — and continue to "Telemetry consent". Don't re-deliver the audit; the next run picks up the new topic.

If briefing creation hits `TOPIC_LIMIT_FREE` or any other `*_FREE` code, run the trial/upgrade flow (see "Tier limits and error handling"). On `*_QUOTA`, surface it and continue (the existing audit still landed).

**Flip the per-repo flag** once the topic is created (or once the user finishes signup + topic creation in this flow). Do **not** flip it if the user picked option 2 or option 3 — those branches handle the flag themselves.

```bash
"<REPO>" flag topic-offered set
```

### 2 — Remind me next session

Don't flip the per-repo flag. Don't touch `SIGNUP_STATE`. The next session in this repo will re-ask with the same wording. Acknowledge briefly ("ok, I'll bring it up next time") and continue to "Telemetry consent".

### 3 — Not for this repo, don't ask again

Flip the per-repo flag — this repo never gets re-offered:

```bash
"<REPO>" flag topic-offered set
```

Other repos still get asked. Tell the user they can re-enable this repo with `header-repo flag topic-offered clear` if they change their mind. Public-default audits keep working unchanged.

### Resumption (deferred signup)

On a later run where `SIGNUP_STATE: pending` and `TOPIC_OFFERED: no`, re-offer with a softer pitch ("you started signup earlier — still want a custom topic for this repo?"). Same three options, same gating. The user can keep deferring as long as they want — option 3 ("not for this repo") is how they silence it.

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

### `header-audit harness`

The premise — *"prompts are technical debt too"*: harness instructions are written for a model and a moment, and they rot silently (workarounds for weaknesses newer models fixed, format-nagging, role puffery, all loaded every turn). Output lines (tab-separated):

- `FILE <path> <bytes> <est_tokens>` — every always-loaded harness file found (`CLAUDE.md`, `AGENTS.md`, settings, commands, subagents, MCP config, editor rules). `est_tokens` is `bytes/4`. Sum these — that cost is paid on **every turn**.
- `IMPORT <parent> <imported-path>` — an `@import` edge. Claude Code (and AGENTS.md) load an `@path` line's target inline, every turn, so the auditor follows imports and emits the imported file as its own `FILE` row. **Include imported files in the always-loaded sum** — the previous scan undercounted by ignoring them.
- `NESTED <path> <bytes> <est_tokens>` — a subdir `CLAUDE.md`/`AGENTS.md`. Loaded **on demand** when the agent works in that subtree, *not* every turn — so count it apart from the always-loaded total (it still rots; flag debt the same way).
- `MODEL <value>` — the model the harness runs: declared in `.claude/settings.json`, else the most recent primary model in the user's transcripts (`~/.claude/projects`). So `MODEL` / `MODEL-STALE` / `MODEL-UPGRADE` fire even when the user pins nothing and rides the default alias.
- `MODEL-STALE <value> <why>` — the model id names a **superseded tier** (Claude 3.x/2.x/instant; early Opus 4.0/4.1). Pure hypothesis-generation: cross-reference the briefing for the current recommended tier and surface a model-migration `[Experiment]`. Conservative by design — current ids aren't flagged.
- `MODEL-UPGRADE <value> <recommended> <why>` — a newer, **same-price, same-family** model has shipped (e.g. Opus 4.5/4.6/4.7 → Opus 4.8). An **opportunity, not debt** (distinct from `MODEL-STALE`): offer the **engine-adoption card** (`/header opus-4.8`) for the grounded case + caveats, then `header-experiment mine --adopt` to prove it on the repo. Conservative — never fires on the current flagship or a superseded tier.
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

- `ECOSYSTEM <name> <manifest>` — detected ecosystems.
- `TOOL <name> <version|-> <ok|too-old|absent>` — package-manager version vs. the minimum that honors a cooldown gate (npm ≥ 11.10, pip ≥ 26.1).
- `GATE <name> <present|absent> <path|->` — whether an install-cooldown / `min-release-age` configuration is in place.

Surface:

- **Supply-chain cooldown.** `GATE npm absent` or `GATE pip absent` → recommend a `min-release-age` / `--uploaded-prior-to` gate so freshly-compromised releases (the chalk/debug, eslint-config-prettier class) are blocked until they're caught. This matters most where the install runs with secrets (CI runners). Get the exact snippet:

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

**Run the scope + harness sanity check before presenting any spend (Step 4).** Only when `COST-SCOPE` is `repo` and `COST-HARNESS` is `claude` should spend lead the scorecard and `ROUTE-CANDIDATE` become a ranked model-routing `[Experiment]`. A `global` scope or a Codex harness-mismatch is **background only**. When it does lead: surface the breakdown first (with `header-cost`'s price-source/freshness + billing-mode notes — see "Cost analytics"), then convert `ROUTE-CANDIDATE` into the model-routing `[Experiment]`. It's a **candidate to prove, never a projected saving**: re-rating the same tokens on a cheaper model is a guess; the honest number comes from `header-experiment` (model-swap). This is the audit's most on-thesis upgrade — it grounds the model-migration hypothesis (the moat's first learning) in the user's real money.

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

The **constructive** scan: where `harness`/`deps`/`cost` find debt to remove, `rails` finds guardrails to *add*. It detects whether the repo has the determinism rails that make AI-written code reliable, and reports the environment the delivery chooser needs. Read the line types here; the full pitch + install flow is in "Determinism rails (guardrails)". Output lines (tab-separated):

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
<AUDIT> rail compound-memory              # the /compound skill + a seed .claude/memory/MEMORY.md
```

Like `gate npm 7` prints the `.npmrc`, `rail <name>` prints the ready artifact — stack-adapted from the `header/scaffold/` templates, with the chosen delivery wiring appended. `precommit-gate` bundles the test ratchet by default (`--ratchet off` to omit); the correctness-critical bits (the `git commit` detector, the corrected skip/xfail regex) travel verbatim in the template. An unknown ecosystem still prints a usable gate with a `TODO` checks block. The SKILL.md flow writes the files; the bin only prints.

### Record findings

Each finding becomes a ledger entry, as documented in the recommendation ledger above. Telemetry aggregates demand consent-gated — **never** sends code, paths, or line content; only counts and kinds.

## Cost analytics (`header-cost`) — beta

> **Beta — the "billing meter" of the optimization platform** (Phase 1 of `docs/experiments-design.md`).
> Costs token usage against a price table, breaks spend down by model. All local; nothing is sent. **Prices are defaults — confirm against current Anthropic pricing**; overridable in `~/.header/prices.tsv`.

Triggered by `/header cost` or "how much am I spending / token spend / what would routing to a cheaper model save". `<COST>` is `header-cost`, next to the preamble's `HEADER_BIN`.

**Verify prices are current *before* presenting any figures.** A stale price makes every number wrong. Before reporting cost:
1. If `HEADER_PRICES_URL` is set, run `"<COST>" refresh` to pull the served table.
2. Otherwise fetch **current** Anthropic pricing — `https://platform.claude.com/docs/en/about-claude/pricing` — and write it to `~/.header/prices.tsv` (`family input output cache_read cache_write`, one line each).

`report` prints the price source + freshness on stderr — **always surface that line with the figures**. Never quote a cost number without saying which prices it used and when they were checked.

**Billing mode — say which, every time.** The `$` figures are **API (pay-per-token) rates**. Two cases:
- **API / Console (pay-per-token):** the `$` is real spend. Savings are real dollars.
- **Claude subscription** (Pro $20 / Max $100 / $200): flat fee, **no** per-token cost. The `$` is a **shadow/API-equivalent** number; the real constraint is **usage limits**. The win isn't dollars, it's **headroom**. The **percentage** savings is identical; only the dollar interpretation changes.

If you don't know which mode the user is on, ask. Don't quote a dollar "saving" to a subscription user as if it were money off their bill.

**Where usage comes from.** The tool reads usage JSONL (`{"model","input_tokens","output_tokens","cache_read_tokens","cache_write_tokens","ts"}`, cache fields optional) and parses raw Claude Code transcripts best-effort (cache-write 5m/1h split priced correctly; legacy Opus 3.x/4.0/4.1 auto-detected and priced apart from current Opus). Zero-setup:

```bash
find ~/.claude/projects -name '*.jsonl' -exec cat {} + | "<COST>" report
find ~/.claude/projects -name '*.jsonl' -exec cat {} + | "<COST>" report --since 2026-05-01
```

**Where the spend is.** `report` ranks models by cost — surface the biggest line and name the obvious lever. The audit-led flow already does this automatically via `<AUDIT> cost` (see "`header-audit cost`"), which wraps this `report` over your transcripts and hands the top line back as a `ROUTE-CANDIDATE`; reach for `header-cost` directly for the full per-model table, `--json`, ad-hoc `cost` tuples, or `refresh`.

**No projections — name the lever, don't guess the saving.** A price re-rating of the same tokens is a guess. `"<COST>" savings` exists only to point at the experiment loop — the user can drive it locally with `header-experiment` (see the next section), and `savings` prints the four-command recipe.

Other subcommands: `"<COST>" refresh [--url U]`, `"<COST>" prices`, `"<COST>" cost <model> <in> <out> [cache_read] [cache_write_5m] [cache_write_1h]`. Add `--json` for machine output.

## Determinism rails (guardrails) — beta

The rest of the audit is **reductive** — it removes prompt-config debt. This is the **constructive** half: it adds *guardrails* that make an AI-written codebase reliable. Driven by `<AUDIT> rails`; surfaced in Step 4 as `[Apply with review] (opinionated)`. Unlike everything else in the skill, these are **conviction, not measurement** — you can't cheaply A/B "should you have a test ratchet" (its value is tail-risk it *prevents*). So present them honestly as Header's house guardrails, not as a proven finding. This is the one part of the audit where we say: take our word for it — it's how we build Header itself.

### Why guardrails (the pitch — lead with this)

A non-deterministic agent **forgets to run things**. Every "always run the tests before committing" line in `CLAUDE.md` is not a rule — it's a *bet that the model complies this turn*, and the odds decay exactly when you need them most (deep in a long session, attention on the bug). No amount of `**IMPORTANT: ALWAYS**` moves that probability to 1; it just costs more tokens to assert harder.

> **A CLAUDE.md instruction lives in the model's *attention* — stochastic, decaying with context. A guardrail lives in the harness's *control flow* — deterministic, constant. Prose asks; a guardrail enforces.**

Promoting a rule from prose to a guardrail is the **one move that's strictly better on both axes Header cares about**: **cheaper** (it leaves the prompt — stops being paid for every turn) *and* **more reliable** (enforced, can't be skipped). So the Header story is **delete *or promote***: dead cargo-cult prose → delete it; prose that encodes a real procedural requirement → promote it to a rail.

**The example to show the user** (prose → guardrail):

```markdown
## Before committing            ← CLAUDE.md: loaded every turn, obeyed *probably*
- Always run black and flake8; fix what they flag.
- Always run the full suite and make sure it passes.
- Never commit with failing or skipped tests.
```

On turn 47 the agent commits without running `black` (the rule is buried), and "make sure it passes" gets satisfied by *deleting the failing test* — prose can't defend against its own misreading. The same rules as `scripts/pre-commit-gate.sh` run deterministically every commit, **block** on failure (the agent is stopped, not reminded), the **ratchet** catches the delete-the-test hack, and the block message says exactly what to run next so the agent self-corrects in-loop. The CLAUDE.md section collapses to one line.

### The three rails (v1)

| Rail | Enforces | When `absent` |
|---|---|---|
| `precommit-gate` | format + lint + test pass before every commit | recommend installing it (bundles the ratchet by default) |
| `test-ratchet` | the agent can't green the suite by deleting / skipping the failing test | if a gate exists but has no ratchet, recommend inserting the block; a fresh `precommit-gate` already includes it |
| `compound-memory` | session learnings get captured (committed `.claude/memory/`) so they stop recurring | recommend the `/compound` skill + seed index — the compounding flywheel; adjacent to Header's own recommendation ledger |

### Delivery: let the user choose (explain the tradeoff)

Both wirings exec the **same** `scripts/pre-commit-gate.sh`, so "both" is one implementation behind two triggers — not double work. They propagate in *opposite* directions, so explain it and let the user pick:

| | Auto-propagates to team on clone | Gates humans + all harnesses | Gates the agent in-loop |
|---|:---:|:---:|:---:|
| **git-native** (`.githooks/` + `git config core.hooksPath .githooks`) | ✗ — each dev runs the `git config` once (a committed `.git/hooks/` is *not* cloned-and-activated) | ✓ | partial |
| **Claude Code PreToolUse** (committed `.claude/settings.json`) | ✓ — every teammate's agent picks it up on clone (modulo Claude Code's hook-trust prompt) | ✗ — Claude Code only | ✓ |
| **both** | ✓ | ✓ | ✓ |

Rule of thumb: solo repo or all-Claude-Code team → PreToolUse alone. Mixed human/agent commits, or multiple harnesses (Codex etc.) → both. Pass the choice to `rail <name> --delivery <git|pretooluse|both>`.

### Not the security risk the audit warns about

The audit flags opaque hooks as the biggest unguarded execution surface (`HOOK` lines). A rail is the **opposite**: committed and reviewable, from this documented template, calling one in-repo script the user can read, with agent-actionable messages. Say this when you recommend it. And note: after the rail is installed, the next `<AUDIT> harness` will list it as a `HOOK` — that's the rail you just added, **not** a new finding; don't re-flag it.

### Install flow

1. Run `<AUDIT> rails`. For each `RAIL absent` (skip `n/a`), check the ledger (`rail-precommit-gate` / `rail-test-ratchet` / `rail-compound-memory`) and drop anything `dismissed`.
2. Present the surviving rails as `[Apply with review] (opinionated)` with the pitch above — comprehensive: offer the full set of missing rails, not just one.
3. On a yes, present the **delivery chooser** (git-native / PreToolUse / both) for gate-based rails, using the `RAIL-ENV git-remote` / `claude` context to recommend a default.
4. Print the artifact: `<AUDIT> rail <name> --ecosystem <RAIL-ENV ecosystem> --delivery <choice>`. **Write the files** it describes (the gate script `chmod +x`, the wiring, the `/compound` skill + seed). Stack-adaptation is automatic from `--ecosystem`; if it's `unknown`, fill in the `TODO` checks block from the detected tooling before writing.
5. Record dispositions in the ledger (`applied` / `dismissed` / `snoozed`). On a commit, append the `Header-Audit-Finding: <key>` trailer.

## Engine-adoption card (`/header opus-4.8`)

A self-contained, repo-independent answer to **"should you move your coding harness to a newer model?"** — launch instance: Opus 4.8. Triggered by `/header opus-4.8` (also `opus-4-8`, `adopt`), or offered from a `MODEL-UPGRADE` audit finding. It does **not** fetch a briefing; it composes a grounded card from a bundled snapshot + the user's own engine, then hands off to `header-experiment mine --adopt` for the actual proof. Full rationale: `docs/engine-adoption-design.md`.

**Render it:**

1. **Read the snapshot.** It ships with the skill at `data/engine-adoption/opus-4.8.md` (relative to the skill dir — the parent of `HEADER_BIN`'s directory). It carries the grounded evidence, the verdict-by-engine rubric, the effort lever, and the caveats, every claim attributed to the Opus 4.8 System Card.

2. **Detect the current engine (the personalization — no repo, no key needed).**
   - **Model:** the `MODEL` line from `<AUDIT> harness`, else `ANTHROPIC_MODEL`, else the `model` in `.claude/settings.json`.
   - **Effort:** `CLAUDE_CODE_EFFORT_LEVEL` → `effortLevel` in settings → the model default (`xhigh` for Opus 4.7, `high` otherwise).
   - **Spend (optional):** `<AUDIT> cost` — if the current model has a `SPEND` line, frame the effort-drop saving against real money.

3. **Present the card.** Lead with the **verdict row matching the detected engine** (the snapshot's "Verdict by the engine you run today" table). Show WHY (the grounded numbers) and — non-negotiable — WATCH (the caveats: toy-eval honesty ≠ long runs, grader-speculation, Terminal-Bench/GPQA, proxy lag). Keep it honest: **this card is a projection**; the verdict for their harness is earned on their tasks.

4. **CTA → prove it.** End on `header-experiment mine --adopt` (mines this repo's history, runs a model+effort A/B of their current engine vs `opus-4-8 @high`; `--sweep` offers a 3rd `xhigh` arm). If they're **not** in a git repo, say so — the card is the answer they get without one (grounded, but a projection); the proof needs a repo.

**Repo-independence is deliberate:** the card runs anywhere (snapshot + local settings/spend); the *proof* needs a repo. The engine (model + effort) is the repo-independent slice of the harness — which is exactly what this decides. **Future models** generalize the same flow: a `<model>` snapshot under `data/engine-adoption/` + `header-experiment mine --adopt --to <model>`.

## Experiments (`header-experiment`) — beta

> **Beta — the experiment loop** (Phase 2 of `docs/experiments-design.md`). Locally A/B-test a harness change (prompt-debt deletion, model swap, etc.) on the user's own tasks: paired-by-task bootstrap CI on per-task cost differences, with success non-inferiority as the merge gate (§6.5). Local-only — every run executes in an isolated `git worktree` and nothing leaves the machine. **Scope:** `mine` (git-history task mining + tests-oracle verifier, §11), `new` (audit-aware scaffolder), `validate`, `run` (`--aa` noise-floor; `setup:`/`teardown:` ephemeral infra), `analyze`, `report`, `merge` (apply arm B after a B-wins verdict). **Not yet:** σ-based power analysis, LLM judges, cross-customer aggregate submit.

### Mine tasks from git history (`mine`) — no hand-authoring

The friction that stopped "continuous" was that `new`/`define` still need the user to write the task **prompt** and name the **verify** command. `mine` removes both (design §11): a real repo already ships its correctness oracle — its **test suite** — and its **git history** is a factory of (task, oracle) pairs. Every commit that fixed code *and* touched tests is a task: check out the **parent**, re-apply only that commit's **test files** (so the new tests fail), and the job becomes "make the suite pass," graded by the repo's own suite. Nobody hand-writes a grader; the human who made the commit already did.

```bash
header-experiment mine <id> --list                       # preview candidate commits (no runs, no writes)
header-experiment mine <id>                              # validate + write a runnable model-swap experiment
header-experiment mine <id> --from <model> --to <model>  # set the A/B arms (default: opus-4-8 vs sonnet-4-6)
```

What it does: scans the last `--limit` commits for fixes touching source + tests (≤ `--max-files`), then **validates** each by checking out the parent, re-applying the fix's test files, and running the suite — keeping only those that **fail** (a real fix exists). Validation **narrows auto-detected runners** (`pytest -q`, `go test ./...`) to each candidate's re-applied test paths — much faster on a big suite, and more precise (an unrelated broken test can't masquerade as a real fix); `--full-validate` forces the whole suite, and the mined spec's *runtime* oracle is always the full suite either way. It writes a complete experiment whose tasks each pin the fix's parent `commit` and carry `apply_from`/`apply_paths`/`lock_paths`; at run time the runner applies the tests before the agent and **re-locks them before grading**, so "make the test pass" can't be won by editing the test (the reward-hacking defense). The default arms are a **model swap** — this is the keystone for "model-routing experiments at scale," the moat's first named learning: *is the cheaper model good enough on this repo's own real fixes?*

**This is the recommended way to start a model-swap experiment** — far less friction than authoring tasks. Reach for `new --kind model-swap` only when you want to test on a *specific* task you have in mind rather than mined history.

### Engine adoption (`mine --adopt`) — "should you move to this model?"

`mine --adopt` is `mine` with the engine-adoption question pre-wired: it detects the model **and effort** the user runs today (arm A), pits it against a target (arm B, default `claude-opus-4-8 @high`), and writes a `kind: engine-swap` experiment. It's the rung-3 proof behind the engine-adoption card (`/header opus-4.8`). No separate verb to learn — it's the `mine` you already know, plus a flag.

```bash
header-experiment mine --adopt                  # A = your current engine, B = opus-4-8 @high
header-experiment mine --adopt --sweep          # + offer a 3rd arm at xhigh (the effort frontier)
header-experiment mine --adopt --to <model> --from <model>[@effort] --effort <level>   # override
```

Why model **and** effort: the System Card's headline is that Opus 4.8 at a *lower* effort can match the prior model at a *higher* one — so the win is often "same quality, cheaper," which only a model+effort A/B can surface. **2-arm by default; `--sweep` offers a 3rd arm** at the next effort up (interactive y/N on a TTY). For a swept (≥3-arm) experiment, **`report <id> --frontier`** is the one-command synthesis: it analyzes every arm vs the control and prints the cheapest arm that holds quality (the effort frontier), with the `merge` command to apply it. (Under the hood the analyzer is pairwise — `analyze`/`report --vs C` give a single A-vs-C comparison into a side `result-vs-C.json`; the canonical `result.json` stays the A-vs-B.) Detection reads `ANTHROPIC_MODEL` → settings `model` → the **most recent model in the user's transcripts** (what actually ran); only if all are empty does it assume `claude-opus-4-7` and **say so** (pass `--from` to correct — arm A is the control). When `merge` finds a B-wins engine swap it **offers to write** `model` + `effortLevel` into `.claude/settings.json` (shows a diff, asks first; `max` stays advisory). The proof needs a git repo (it mines real fixes); outside one, point the user at the card.

Scope honesty (state it when you surface results): mine's per-candidate check confirms the new tests *fail at the parent* (a FAIL_TO_PASS exists); it relies on `run --aa` to expose flaky/baseline-broken tasks (a task arm A can't pass either). The suite runs in a bare `git worktree`, so dep dirs (`node_modules`, `.venv`, …) are auto-symlinked via `worktree_include`; if validation finds nothing, the suite usually needs a build/env the worktree lacks — pass a `--verify` that runs standalone. Tier-1 proves correctness on covered behavior, not taste — don't overclaim.

**Worktree-isolation requirement (a real footgun).** mine (and the A/B run) only measure the *worktree's* code. A **PEP 660 editable install** — `pip install -e .` with a modern backend installs a `sys.meta_path` finder pinned to ABSOLUTE source paths — or any globally-installed copy of the package **defeats this**: inside every worktree, imports resolve to your *current* tree, not the checked-out parent/arm. mine now detects the signature (every candidate's re-applied tests PASS at its parent → it stops early and names the cause) instead of churning the whole suite for nothing. `worktree_include: venv` does **not** fix it (the finder's paths are absolute). The fix is to make the install path-based: `pip install -e . --config-settings editable_mode=compat` (revert with `pip install -e .`), or run mining inside a per-worktree venv. If you don't fix it, a later A/B would silently test the parent repo's code in both arms — the worst false "no difference."

### From audit finding to scaffolded experiment

The audit's `[Experiment]` findings are the input. When the user says "let's test that" on a finding, **don't make them retype what the audit already knows** — call `header-experiment new --kind ...` with the finding's payload pre-filled. The wizard auto-detects the verify command from the project's manifests (`package.json` → `npm test`, `Cargo.toml` → `cargo test`, etc.) and only asks for the one bit the audit can't infer: **which task to run the agent on**.

Concrete invocations by finding kind:

- **Prompt-debt deletion** (a `HIT` from `header-audit harness` — cargo-cult lines in `CLAUDE.md`/`AGENTS.md`):
  ```bash
  header-experiment new "<ledger-key>-$(date +%Y%m%d-%H%M%S)" \
    --kind prompt-debt-deletion \
    --file <relative-path-from-HIT> \
    --lines <line1,line2,...> \
    --description "<short title>" \
    --ledger-key <key> \
    --task <task-prompt-or-path> \
    --verify <verify-cmd>
  ```
  Arm A = current state. Arm B = the file with those lines stripped (the wizard does the sed for you and writes `arms/B/<file>`). **The verify task must exercise the deleted lines** — see the discrimination gotcha below; a generic `npm test` won't catch adherence drift.
- **Model swap** (audit/briefing-derived: "consider routing this task class to a cheaper model"):
  ```bash
  header-experiment new "<ledger-key>-$(date +%Y%m%d-%H%M%S)" \
    --kind model-swap \
    --from <current-model> \
    --to <proposed-model> \
    --description "<short title>" \
    --ledger-key <key> \
    --task <task-prompt-or-path> \
    --verify <verify-cmd>
  ```
- **Other** (major dep upgrade, behavioral rewrite — anything where you need to construct arm B's overrides by hand): fall back to the generic flow:
  ```bash
  header-experiment new "<id>" \
    --arm A:<current-model> --arm B:<proposed-model>:arms/B \
    --task <path-or-inline> --verify <cmd>
  ```
  Then prepare `~/.header/experiments/<id>/arms/B/` with the override files (copied into the worktree before the agent runs).

`--task` accepts either a path (resolved relative to the repo first, then the experiment dir) or a one-line inline prompt (written to `<exp_dir>/tasks/tN.md`). **`--task` is repeatable** — for crisper CIs target ≥3 tasks (the bootstrap CI's noise floor drops sharply moving from N=1 to N=3 to N=5). If you have real prior task transcripts or recent feature specs in the repo, use those — more realistic measurement than synthetic prompts.

**Power tiering.** Analyses below 5 paired tasks aren't refused — they're caveated. N=1 paired-by-task is genuinely degenerate (CI is a single point); N=2-4 is wide-but-honest and surfaces a `WIDE CI / LIMITED POWER` flag in the report. **For an A/A noise-floor check with only 1 task × K replicates**, the runner switches to a within-task replicate-level bootstrap automatically, which gives real bias-detection power without needing multiple tasks.

**Worktree isolation gotcha.** `git worktree add` only brings *tracked* files. If your verify command needs `venv/`, `node_modules/`, `.env`, or editable-installed packages, set `worktree_include: venv, .env, ...` in the spec — those paths get symlinked from the repo into each run's worktree. Without it, verify may silently test the parent repo's code instead of arm B's edits (the worst kind of false success).

**Stateful experiments — `setup:` / `teardown:` (ephemeral infra).** `worktree_include` handles *files*; a DB-touching task needs an *isolated service*, not the repo's real database. Add `setup:` (a shell command) to the spec's top block: its stdout `KEY=VALUE` lines are captured and exported into every run's **adapter and verifier**, so the agent and the oracle both hit a throwaway DB/branch — never prod or beta. `teardown:` destroys it and is **guaranteed to run** (an `EXIT`/`INT`/`TERM` trap fires it even on Ctrl-C). `setup_scope:` is `experiment` (provision once for the whole matrix — fine for read-only or self-resetting tasks) or `run` (provision + tear down per `(task, arm, rep)` — required for **write-heavy** tasks, where one run's writes would otherwise contaminate the next; this multiplies infra churn, so guaranteed teardown matters). Example: `setup: neonctl branches create … -o json | jq -r '"DATABASE_URL=" + .connection_uris[0].connection_uri'` with a matching `teardown: neonctl branches delete …`. **Footgun:** a `DATABASE_URL` you inject this way is **shadowed by a `.env` you symlinked via `worktree_include`** if the app reads `.env` over the process env — have `setup` write the `.env`, or don't symlink it. Tool-managed provisioning is also how you avoid the "is this connection string the throwaway or prod?" guessing game — never hand-edit `.env` and eyeball endpoint IDs.

**Discrimination gotcha (prompt-debt deletions) — the deletion-side twin of the worktree trap.** A trim experiment only measures something if the verify task *exercises the trimmed instruction*. Delete a `MUST self-verify` line, then run a task that never needed self-verification, and you get "3/3 both arms" — which proves the task was easy, not that the cut was safe. The failure is on **both** axes, not just cost: the cost CI is sub-noise *and* the success rate is non-discriminating, so no outcome of the experiment can move the decision. Worse, a regression-style verify (`npm test`) is **blind to adherence drift** — the suite passes in both arms even if arm B quietly stops obeying the rule. Before running, ask: *would this task plausibly fail if the agent ignored the deleted lines?* If no, the experiment can't see its own risk — either pick a task that **requires the instruction to fire**, or treat the change as `[Apply with review]` (the diff is the evidence). Infra-dependent mandates ("self-verify via curl", "visual-check the page") need the **stack brought up inside the worktree** — that's a *supported* path, not a dead-end: `worktree_include` symlinks the files, and per-experiment ephemeral DBs/branches come from the `setup:`/`teardown:` lifecycle above. It carries a real wall-clock + provisioning cost, so weigh it — don't reflexively bail to `[Apply with review]` just because infra is involved. Stack-up is necessary but **not sufficient**, though: if the run adapter (often a one-shot headless invocation) doesn't actually *perform* the mandated work, arm A's cost collapses onto arm B's and you get a false "the mandate is free" — the **cost** axis goes non-discriminating exactly as the success axis can. `validate` and `run` print this warning automatically when an arm trims a `CLAUDE.md`/`AGENTS.md` — detected by diffing the override against the repo, so **hand-rolled specs are caught too** — and escalate when the deleted text carries emphatic mandates (`MUST`/`NEVER`/`ALWAYS`).

**Guardrail-value questions ("is this mandate earning its cost?").** Don't reach for an A/B. The question decomposes into *cost* (cheap — measure **one** real execution of the mandated work) and *benefit* (tail-risk insurance: the rate it prevents a bug that would otherwise ship × that bug's cost). A small-N A/B can't estimate a rare-event rate, and — per the cost axis above — a headless adapter often won't even incur the cost, so the run comes back falsely "free." Default to **measuring one execution's cost directly and reasoning about the benefit qualitatively**, keeping the guardrail unless the cost clearly isn't worth the protection. `new --kind prompt-debt-deletion` and `report` surface this recommendation when the deleted text is an emphatic mandate.

After the scaffold prints, walk the user through the four-step loop:

```bash
header-experiment validate <id>                      # lint
header-experiment run <id> --aa                      # noise-floor check FIRST (§3) — must be clean
header-experiment run <id>                           # the A/B (--jobs N parallelizes (task,rep) blocks;
                                                     #  arms stay sequential per pair, so pairing holds)
header-experiment analyze <id> && header-experiment report <id>
```

Surface these points when interpreting the report:
- The CI on **B − A cost** (per-task paired bootstrap, 95%) is the effect — the diff itself is meaningless without it.
- **Decision rule** (§6.5): merge B iff the cost CI's upper bound is below 0 AND success-rate diff's lower CI bound is ≥ −δ. Anything else is **"no proven win"**, not "B wins."
- **Conservative savings rate** (= `max(0, -upper_CI(diff_cost))`) is the figure that survives an audit — never quote the optimistic tail.
- A **noisy A/A** (CI excludes 0) means the harness is biased — *fix the harness before trusting any A/B*. This is the most common silent failure mode.
- **Agent-error rows (timeout / crash) are excluded from cost means but count on the success axis** with the verifier's verdict — a flaky arm can't look non-inferior by crashing its way out of the sample. The report shows both pairings ("N cost / M success") when they differ.

The runner spends real tokens — the cost gate confirms before launching. Don't auto-`--yes` for the user. Even with `--yes`, the runner still prints the full cost/power disclosure (it skips the confirmation *prompt*, not the disclosure), and if a prior `--aa` result exists it surfaces the **measured noise floor** at the A/B gate — so an effect smaller than the harness's own run-to-run noise is visible *before* the spend, not discovered at `analyze`.

On a B-wins verdict, `header-experiment merge <id>` applies arm B's overrides to the repo — it shows the unified diff first, asks for confirmation, refuses any non-B-wins verdict unless `--force`, and prints a suggested `git commit` with the `Header-Audit-Finding:` trailer when the experiment came from an audit finding. It does **not** auto-commit; you retain the final say.

### Sync experiments to your account — beta, automatic when a key is present

Experiments sync to the user's Header account so they show up in the web UI — a live-updating record of *which experiment, testing which hypothesis, from which goal/topic/briefing, on which repo and machine, and how it came out*. Nothing runs server-side; the runner stays local. This is the user's own identified dashboard, distinct from the (still-anonymized, still-future) cross-customer aggregate submit.

**It is automatic, not a prompt.** Every lifecycle change — `new`, `define`, `validate` (the "I edited the spec" hook), `run`, `analyze`, `merge` — fires a background sync, gated on:

- **`HAS_KEY: yes`** (and `experiment_sync` is `auto`, the default) → the tool syncs and prints a faint `⤴ dashboard: …` status line. **Don't ask permission per edit** — the user opted in by configuring a key. Surface the line if useful; mention the dashboard URL on success.
- **`HAS_KEY: no`** → the tool prints a one-time per-experiment recommendation to connect an account. **Reinforce it** — route through the post-audit signup flow — but never block the experiment. Recommend, don't require.

The lifecycle `status` (`defined → run → analyzed → merged`) is part of every sync, so the UI shows each experiment's last-known state. A local `~/.header/experiments/<id>/.last-sync` marker (`<iso> <http_code>`) records the last sync result for offline inspection.

**Opt-out.** `header-config set experiment_sync off` disables all auto-sync (manual `push` still works); `HEADER_EXPERIMENT_NOSYNC=1` disables it for one invocation / CI. `experiment_sync` is **personal-only** — a committed team config cannot turn it on for teammates.

**The privacy contract — say it plainly.** Sync sends metadata only: the experiment id/kind/description, arm models + override **paths** (not contents), task **titles** + a sha256 + byte count, the hypothesis (the full claim in words, plus its audit-finding provenance), the topic/goal/briefing it traces to, the repo's git-remote identity + commit, the machine (install id + hostname/os/arch), and the analyzed result (verdict + CIs). **Task prompt bodies, override file contents, and agent logs never leave the machine.** Task titles resolve authored → derived → id: if a `[task:…]` block has a `title:` line you (or the user) wrote, it's sent verbatim (zero-leak); otherwise a one-line summary is *derived* from the prompt's first heading (descriptive, low-leak); otherwise the task id is the floor. **If the prompt's first line could embed sensitive specifics, author a `title:` first** so the synced label is one you control.

**Help the lineage along.** The hypothesis *statement* (the dashboard headline) is the spec's own `hypothesis:` field — falling back to `description` — so it syncs directly and never depends on the ledger. Set it at scaffold time with `--hypothesis` (`new`/`define`), or edit the spec. The audit-finding provenance (title + source_url + disposition) and the topic/briefing are recovered from the recommendation ledger via the spec's `ledger_key`. When the session resolved a topic/goal/briefing the ledger doesn't have, a manual `push` can supply them (flags win over the ledger):

```bash
header-experiment push <id> --topic <topic_id> --goal <goal_id> --briefing <briefing_id>
header-experiment push <id> --dry-run    # print the exact JSON payload (no key needed)
header-experiment push --all             # sync every local experiment now
```

**Errors (auto-sync is always best-effort).** No key → recommend + skip (never an error). `404`/`405` → unexpected now that the endpoint is live — usually a stale deployment or a proxy in the way (or a `HEADER_API_BASE` override); the status line says so, the experiment is safe locally, and it retries on the next edit. A `*_FREE` code → dashboard sync is Pro; run the trial/upgrade flow (see "Tier limits"). Sync never blocks or fails the experiment loop.

### Aggregate submit — the proven-changes library (beta, opt-in, anonymized)

The cross-customer pool behind `PROVEN` lines (design §7.3): each consenting user contributes the **anonymized effect size** of an analyzed experiment, and the library serves the pooled evidence back through briefing-supplied 6-field patterns — so a change one user proved becomes "[proven across N repos]" in everyone's audit, and nobody re-runs a $60 A/B for a change the pool already measured. **Distinct from account sync** (`push` is the user's own identified dashboard): aggregate carries **no identity at all**.

```bash
header-experiment aggregate <id> --dry-run   # preview the exact payload (nothing sent)
header-experiment aggregate <id>             # asks y/N (or --yes); needs an analyzed result
<HEADER_BIN> set aggregate_submit on         # opt in: auto-submit after each analyze
```

**The privacy contract — stronger than sync's.** Sent: change kind, the **curated** category (the ledger key only when it names a known pattern id — user-typed keys never leave), ecosystem label, harness, task class, verifier tier, arm engines (public model ids + effort), N/replicates/δ, and the result's verdict + means + CIs (`per_task` is stripped — mined task ids embed commit shas). Never sent: installation id, hostname, repo identity, prompts or hashes of them, override paths, or any free text (`description`/`hypothesis` stay local). The POST is **unauthenticated by design** — identity stays off the wire entirely; the server applies small-cohort (k-anonymity) protections before serving pooled claims. `aggregate_submit` is **personal-only** — a committed team config cannot enable it. Default **off**; `HEADER_EXPERIMENT_NOSYNC=1` disables it for one invocation/CI. _(The receiving endpoint is landing server-side; until then the call exercises the contract and records the attempt in `.last-aggregate`.)_

## Browse public topics

List all public topics:

```bash
curl -s https://joinheader.com/api/v2/topics/public/catalog
```

Each entry has `id`, `name`, `description`, `subscriber_count`.

Get details for a specific topic (includes latest briefing summary):

```bash
curl -s https://joinheader.com/api/v2/topics/public/{topic_id}
```

The response includes the topic `name`, `description`, and `latest_briefing` details.

## Custom briefings (API key required)

API reference for authenticated workflows. Most of this is wired into the audit-led flow above ("After the audit"); use this section for the underlying API contract.

### API key resolution

Each authenticated call needs the key. Run once at the start of any shell making an authenticated call:

```bash
[ -n "${HEADER_API_KEY:-}" ] || HEADER_API_KEY="$(sed -n 's/^HEADER_API_KEY=//p' "${HEADER_HOME:-$HOME/.header}/credentials" 2>/dev/null)"
export HEADER_API_KEY
```

Env first, then the credentials file — which is **parsed, never sourced**. If it resolves empty, tell the user no key is configured and route them through the post-audit signup flow.

### Tier limits and error handling

Authenticated endpoints return structured error codes on tier limits:

| Suffix | HTTP | Meaning | Recovery |
|---|---|---|---|
| `*_FREE` | 403 | Caller is on the free tier; action is Pro-only. | Ask the user — start the free **trial** (only if the error response includes `can_start_trial: true`) or **upgrade** directly to Pro. **Never auto-pick a path.** On *trial* → `POST /api/v2/billing/trial/start`, then retry. On *upgrade* → `POST /api/v2/billing/create-checkout`, parse the returned URL, open it (portable: `open` / `xdg-open` / `start`). |
| `*_QUOTA` | 429 | Paid tier but at the cap (e.g., 10 topics, 7 manual briefings per rolling 24 h). | Tell the user. Suggest: wait, delete a topic, or email `info@joinheader.com` if the use case justifies a higher cap. |

**Concrete codes:**

| Endpoint | Free-tier code | Paid-cap code |
|---|---|---|
| `POST /api/v2/topics/` | `TOPIC_LIMIT_FREE` | `TOPIC_LIMIT_QUOTA` |
| `POST /api/v2/goals/{id}/briefings` | `MANUAL_BRIEFING_FREE` | `MANUAL_BRIEFING_QUOTA` |
| `PUT /api/v2/topics/{id}` | `EDIT_FREE` | — |
| `PUT /api/v2/goals/{id}` | `EDIT_FREE` | — |

**`https://joinheader.com/docs` is the canonical source of current error codes and recovery flows.** Fetch the docs page on any unknown code:

```bash
curl -sS https://joinheader.com/docs
```

#### TOPIC_LIMIT_FREE recovery

`POST /api/v2/topics/` returns `403` with `error.code: "TOPIC_LIMIT_FREE"`; the response also includes `can_start_trial`. Ask:

> Custom topics need a Pro account, and you're on the free tier. Pick one:
>
> 1. **Start the free trial now** (recommended — no credit card needed)
> 2. Upgrade to Pro directly

Trial (if `can_start_trial: true`):

```bash
curl -sS -X POST https://joinheader.com/api/v2/billing/trial/start \
  -H "Authorization: Bearer $HEADER_API_KEY"
```

Then retry the original `POST /api/v2/topics/`. Upgrade:

```bash
resp=$(curl -sS -X POST https://joinheader.com/api/v2/billing/create-checkout \
  -H "Authorization: Bearer $HEADER_API_KEY")
URL=$(printf '%s' "$resp" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
if [ -n "$URL" ]; then
  if   command -v open     >/dev/null 2>&1; then open "$URL"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
  elif command -v start    >/dev/null 2>&1; then start "$URL"
  else echo "Open $URL in your browser to finish checkout."
  fi
fi
```

The same trial-vs-upgrade pattern applies to any `*_FREE` code.

### Setup

Create an API key with **read + write** access from **Settings ▸ API Keys** at [joinheader.com](https://joinheader.com) — write is required to create custom topics:

```bash
export HEADER_API_KEY="hdr_sk_..."
```

### Create a custom topic

Before POSTing, ask whether to include any custom sources on top of the default source group:

> Add custom sources to this briefing topic? You can include additional RSS feeds, YouTube channels, Reddit subs, or existing Header source groups / source IDs alongside the default group (which covers AI agent frameworks, MCP, and coding tools).
>
> 1. **No, just the default sources** (recommended)
> 2. Yes — I'll provide them

Topics link **source groups**, not individual sources. The create body takes `source_group_ids` (min 1):

- Existing **source group IDs** → add to `source_group_ids` alongside the default.
- Individual **source IDs** or **new feed URLs** → put them in a group first ("Add a source"), then include that group's id. Or let Header propose a tailored group: `POST /api/v2/sources/recommend` (`topic_name`, `goal_description`) → `POST /api/v2/sources/recommend/commit` returns a new `group_id`.

```bash
curl -s -X POST https://joinheader.com/api/v2/topics/ \
  -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My Project Briefing",
    "source_group_ids": ["64981a34-3b8b-4064-a391-22f4534c229b"],
    "goal_description": "Focus on developments relevant to [describe your project and tech stack]"
  }'
```

The default source group (`64981a34-...`) covers AI agent frameworks, MCP, coding tools. The response includes `first_briefing_id` — generation runs asynchronously.

### Team config (`.header/config`) — share a topic with your team

The personal binding from "After the audit" lives under `~/.header/` — it never leaves the machine, so a teammate who clones the repo gets nothing. To share with everyone on the repo, commit a `.header/config` at the repo root.

The post-audit flow offers to scaffold this when a topic is created in a shared repo. To do it manually:

```bash
"<HEADER_BIN>" team-init <new_topic_id>     # creates ./.header/config with default_topic
git add .header/config && git commit -m "Add Header team config"
```

**Team-relevant settings only.** Because the file is committed, only the allow-list is honored: `default_topic`, `staleness_days`, `schedule_frequency_days`, `language`. Personal preferences and **anything consent-, code-, or egress-related** (`telemetry`, `auto_update`, `auto_tune`, `update_check`, `experiment_sync`, `aggregate_submit`) are **ignored** by design — `header-config team-show` makes its effective contents auditable.

**Precedence.** `TEAM_TOPIC` sits **below** a personal `REPO_TOPIC` and **below** any env var, but **above** the personal default. Same for `staleness_days` and `language`.

**Security.** The committed file is **read as data only** (`grep`/`sed`, never sourced); only allow-listed keys are honored.

### Bound repos — freshness & schedule

Runs at session start **only** when the preamble echoed a non-empty `REPO_TOPIC` **or** `TEAM_TOPIC` and a key is available. Team topic behaves like a personal binding here — substitute `TEAM_TOPIC` for `{REPO_TOPIC}` below when Step 0 resolved that (just don't `header-repo clear` a team topic on `404`; tell the user to fix `.header/config` instead).

**1. Fetch the bound topic and check freshness.**

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $_HK" \
  https://joinheader.com/api/v2/topics/{REPO_TOPIC}
```

- `404` → topic deleted server-side. Tell the user, run `"<REPO>" clear`, fall back to the default topic.
- Otherwise read `default_goal_id` and `latest_briefing.generated_at`. Compare to the last-seen marker:

```bash
_SEEN="$("<REPO>" seen)"
```

If `generated_at` is newer than `_SEEN` (or empty), there's a **new briefing since the user last visited this repo** — say so ("📰 New briefing for this repo, generated <date>"), enrich the audit via Step 2 using `latest_briefing` (fetch by id with `Accept: text/markdown`). Record what was shown:

```bash
"<REPO>" seen "<generated_at of the briefing just delivered>"
```

**2. Schedule** — handled inside the post-audit chain. To change/stop later: `PUT /api/v2/goals/{default_goal_id}` with a new `schedule_frequency_days`, or `{"schedule_enabled": false}`.

### Add a source

`/header add-source <url>` (or "add this source: <url>") feeds a URL into the user's topic. Requires a key.

```bash
# 1. Preview (detect type, verify the URL)
curl -sS -X POST https://joinheader.com/api/v2/sources/preview \
  -H "Authorization: Bearer $HEADER_API_KEY" -H "Content-Type: application/json" \
  -d '{"url":"<url>"}'
# 2. Create the source
curl -sS -X POST https://joinheader.com/api/v2/sources/ \
  -H "Authorization: Bearer $HEADER_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"<name>","type":"<type>","url":"<url>"}'   # → returns the source id
# 3. Add it to a source group the topic's goal already references
curl -sS -X POST https://joinheader.com/api/v2/source-groups/{group_id}/members \
  -H "Authorization: Bearer $HEADER_API_KEY" -H "Content-Type: application/json" \
  -d '{"member_id":"<source_id>"}'
```

Pick a group the user owns. If none editable, create one (`POST /api/v2/source-groups/`), add the source, then `PUT /api/v2/goals/{goal_id}` with `source_group_ids` including the new group. If multiple topics, ask which. On `*_FREE`, run trial/upgrade.

### Check briefing status

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $HEADER_API_KEY" \
  https://joinheader.com/api/v2/briefings/{briefing_id}
```

`status` is `IN_PROGRESS`, `COMPLETED`, or `FAILED`.

**Markdown rendering:** authenticated path honors `Accept: text/markdown`:

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Accept: text/markdown" \
  https://joinheader.com/api/v2/briefings/{briefing_id}
```

(Public path returns JSON only.)

### Polling IN_PROGRESS briefings

`POST /api/v2/goals/{id}/briefings` returns `201` with `estimated_duration_seconds` (ETA). **The ETA is static** — fixed at create time, doesn't count down. Compute remaining as `estimated_duration_seconds - (now - created_at)`. Add a small buffer. Null on briefings predating the field — fall back to 300s.

**Cadence:** sleep `remaining` + buffer before the first poll, then poll every 30s. Give up at ~2× the ETA past `created_at`.

**Blocking pattern** (user is waiting):

```bash
resp=$(curl -sS -H "Authorization: Bearer $HEADER_API_KEY" \
  -X POST https://joinheader.com/api/v2/goals/{goal_id}/briefings)
briefing_id=$(echo "$resp" | jq -r .id)
eta=$(echo "$resp" | jq -r '.estimated_duration_seconds // 300')
sleep "$(( eta + 15 ))"
deadline=$(( $(date +%s) + eta ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  status=$(curl -sS -H "Authorization: Bearer $HEADER_API_KEY" \
    "https://joinheader.com/api/v2/briefings/$briefing_id" | jq -r .status)
  case "$status" in
    COMPLETED) break ;;
    FAILED) echo "Briefing failed"; exit 1 ;;
  esac
  sleep 30
done
```

**Non-blocking pattern** — for the post-audit chain, which intentionally fills the wait with the schedule/team-config questions:

1. Tell the user the briefing is generating, including the ETA.
2. Record `briefing_id` and `created_at`.
3. Ask the chained questions (schedule, team-config).
4. Check back after the ETA — fetch by ID and confirm completion.

**Claude Code** automates step 4 without busy-waiting:

- **Background loop:** run the poll loop as a background job (`Bash` with `run_in_background: true`); it sleeps `remaining` + buffer, polls every 30s, re-invokes you on exit.
- **Timer:** `ScheduleWakeup` with `remaining` + buffer; the agent wakes, does one GET, and confirms — or reschedules a short delay if still `IN_PROGRESS`.

Other harnesses: record `briefing_id`, fetch on next invocation.

### Generate a new briefing

```bash
curl -sS -w "\n%{http_code}" -X POST -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  https://joinheader.com/api/v2/goals/{goal_id}/briefings \
  -d '{"max_entries": 5, "max_age_days": 7}'
```

Body fields optional — omit the body for defaults.

| Body field | Notes |
|---|---|
| `max_entries` | cap source entries |
| `max_age_days` | only entries from the last N days |

Returns `201` with `status: IN_PROGRESS` + ETA — then poll.

### Update a goal

```bash
curl -sS -w "\n%{http_code}" -X PUT https://joinheader.com/api/v2/goals/{goal_id} \
  -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"description": "Updated focus areas...", "keywords": ["MCP", "agent memory"]}'
```

### Sync an experiment (`POST /api/v2/experiments`)

Account-scoped, idempotent **upsert** keyed by `client_key` (`<installation_id>:<experiment_id>`) so re-syncing the same experiment as it progresses (defined → run → analyzed → merged) updates one record. Driven automatically by `header-experiment` on each lifecycle change when a key is present (and by manual `push`); this is the underlying contract. **Metadata only — never code, prompt bodies, override contents, or logs.**

```bash
curl -sS -w "\n%{http_code}" -X POST https://joinheader.com/api/v2/experiments \
  -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  -d @- <<'JSON'
{
  "v": 1,
  "client_key": "<installation_id>:<experiment_id>",
  "skill_version": "0.14.0",
  "submitted_at": "2026-05-28T18:22:45Z",
  "experiment": {
    "id": "slim-claude-md-20260527-141627",
    "kind": "harness-change",            // harness-change | model-swap | generic
    "description": "Slim CLAUDE.md: compress 4 skill-redundant sections…",
    "status": "analyzed",                // defined | run | analyzed
    "replicates": 3,
    "non_inferiority_margin": 0.02,
    "commit_ref": "HEAD",
    "arms": [
      {"label":"A","model":"","role":"control","overrides":null},
      {"label":"B","model":"","role":"treatment","overrides":"arms/B"}
    ],
    "tasks": [
      {"id":"t1","title":"Add a briefing_count field to the v2 Goal model",
       "title_source":"derived","verify":"pytest tests/v2/ -x -q",
       "prompt_ref":"tasks/t1.md","prompt_sha256":"b2938df7…","prompt_bytes":308}
    ]
  },
  "hypothesis": {                        // present whenever a statement exists (it almost always does)
    "statement":"Slimming CLAUDE.md keeps success non-inferior at materially lower per-turn token cost",
                                          //   ↑ the full claim in words — the dashboard headline. The
                                          //     spec's `hypothesis:` field, falling back to `description`.
    "ledger_key":"slim-claude-md",       // ↓ provenance — blank unless the experiment traces to a finding
    "title":"Slim CLAUDE.md — 644 lines / ~9,739 tokens loaded every turn",
    "source_url":"https://www.youtube.com/watch?v=…",
    "disposition":"wanted"
  },
  "audit_basis": {"topic_id":"1991163f-…","goal_id":"","briefing_id":"3c9b6bbd-…"},
  "repo":    {"key":"github.com/me/repo","name":"repo","branch":"main","commit":"5214a29"},
  "machine": {"installation_id":"<uuid>","hostname":"…","os":"linux","arch":"x86_64"},
  "result":  { /* result.json verbatim: verdict, cost/success CIs, per_task — or null */ }
}
JSON
```

Expected success response (`200`/`201`): `{"id":"<server_id>","client_key":"…","url":"https://joinheader.com/experiments/<server_id>","status":"stored"}`. Surface the `url`. `goal_id` may be empty — the server can resolve the goal from `briefing_id` (a briefing belongs to a goal), or the client supplies it via `--goal`. Free-tier callers may get `EXPERIMENT_SYNC_FREE` (Pro-only) — run the trial/upgrade flow.

### Goal auto-tuning

Feed what the user applies/dismisses (the ledger) back into the goal so future briefings sharpen. Requires an API key + a custom goal; opt-in via `auto_tune`.

**Offer it once** when `<LEDGER> list --action applied --since-days 90` has 3+ entries, `auto_tune` is not already set, and no `~/.header/.autotune-offered` marker exists:

> You've applied several recommendations. Want Header to auto-tune this topic's focus from what you act on, so future audits get sharper?

On yes → `<HEADER_BIN> set auto_tune true`. Always `touch "${HEADER_HOME:-$HOME/.header}/.autotune-offered"`.

**When `auto_tune` is `true`** (key + custom goal exist), after delivering the audit, refine the goal from the ledger:
- Applied keys (`<LEDGER> list --action applied --since-days 90`) → add/emphasize keywords.
- Dismissed keys (`<LEDGER> list --action dismissed --since-days 90`) → de-emphasize.
- One `PUT /api/v2/goals/{goal_id}`, **merging** existing `keywords` / `description` (don't replace).

Best-effort: skip silently if no key, no custom goal, or no new signal. When you tune, say so. Tuning never blocks the audit.

### Since-last digest

For "what's new since I last checked" (and cron / `ScheduleWakeup` shapes): pass the last-run timestamp to surface only changes.

```bash
_HH="${HEADER_HOME:-$HOME/.header}"; _SINCE="$(cat "$_HH/.last-run" 2>/dev/null || echo)"
curl -sS -H "Authorization: Bearer $HEADER_API_KEY" \
  "https://joinheader.com/api/v2/topics/dashboard${_SINCE:+?since=$_SINCE}"
```

Surface topics whose `next_action` is `briefing_ready`; if nothing, say "nothing new since &lt;time&gt;" and stop. The skill writes `.last-run` after each audit.

### Scheduled / agent loop

For agents on a cron or scheduled trigger, use `GET /api/v2/topics/dashboard?since=<iso8601>` and the server-computed `next_action`:

| `next_action` | Meaning | Behavior |
|---|---|---|
| `briefing_ready` | New completed briefing available. | Fetch `latest_briefing.id`; run the audit flow with it as enrichment. |
| `briefing_failed` | Most recent generation failed. | Tell the user; suggest re-trigger via `POST /goals/{id}/briefings`. |
| `briefing_in_progress` | Still generating. | Apply the polling cadence above. |
| `nothing` | No change since `?since`. | Skip. |

**Set `HEADER_NONINTERACTIVE=1`** in scheduled / unattended environments — the preamble reads it and suppresses every prompt (`CI=1` is treated the same way).

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $HEADER_API_KEY" \
  "https://joinheader.com/api/v2/topics/dashboard?since=2026-05-01T00:00:00Z"
```

For full API documentation, see [joinheader.com/docs](https://joinheader.com/docs).

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

> **Source of truth:** the field names, types, endpoints, and error codes here are a point-in-time snapshot. If the live API disagrees, **trust the API and fetch the latest contract from [joinheader.com/docs](https://joinheader.com/docs)** (e.g. `curl -sS https://joinheader.com/docs`, or the OpenAPI spec at `https://joinheader.com/api/v2/openapi.json`). Adapt to what the docs say; don't force the call to fit this snapshot.

### BriefingResponse

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Briefing UUID |
| `goal_id` | string | Parent goal UUID |
| `status` | string | `IN_PROGRESS`, `COMPLETED`, or `FAILED` |
| `summary` | string | Full markdown briefing text |
| `key_developments` | string | JSON-encoded array — parse from string into structured list; feeds the audit cross-reference in Step 4 |
| `source_articles` | array | Source articles used (title, url, metadata) |
| `estimated_duration_seconds` | int? | Server-computed ETA on the create response. Static — fixed at create time; compute remaining as `estimated_duration_seconds - (now - created_at)`. Null on completed/public briefings and pre-field briefings. |
| `source_count` | int? | Number of sources the ETA was based on. Null on completed/public briefings and pre-field briefings. |
| `stats` | object | Processing statistics (model, tokens, content window, etc.) |
| `is_public` | bool | Whether the briefing is publicly accessible |
| `created_at` | datetime | When generation was requested. Anchor for the remaining-ETA computation. |
| `generated_at` | datetime | When the briefing was generated |

### TopicCatalogItem

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Topic UUID |
| `name` | string | Topic name |
| `description` | string | What the topic covers |
| `source_count` | int | Number of source groups |
| `total_source_count` | int | Total individual sources |
| `subscriber_count` | int | Number of subscribers |

### ExperimentSyncResponse (`POST /api/v2/experiments`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Server-assigned experiment record id |
| `client_key` | string | Echoes the request's idempotency key (`<installation_id>:<experiment_id>`) |
| `url` | string | Web UI link to the synced experiment — surface this to the user |
| `status` | string | `stored` (created or updated) |

The request body is the `header-experiment push` payload documented under "Sync an experiment (`POST /api/v2/experiments`)". The receiving endpoint is **live** (it upserts on `client_key` and returns the web-UI `url` — surface it). A `404`/`405` from it now indicates a stale deployment or a proxy in the way, not a missing handler; the client's retry-on-next-edit behavior still applies.
