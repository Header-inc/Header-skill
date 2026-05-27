---
name: header
version: 0.10.2
description: "Audit and optimize the AI coding agent's own setup — CLAUDE.md, model choice, dependencies, settings — for prompt-config debt and supply-chain risk. Each invocation runs the audit, enriched by the latest agentic-coding briefing relevant to your stack. Public access needs no auth; authenticated workflows use an API key."
when_to_use: "Use to audit and improve the agent's own setup. Triggers include audit, audit my setup/agent/harness, optimize codebase, reduce token cost, supply-chain risk, dependency upgrade, CLAUDE.md or prompt debt, latest best practices, what's new in agents/MCP/coding tools. Runs on /header, /header-audit, or the legacy /header-briefing. Pass a topic name, UUID, or briefing URL to swap the enrichment topic; otherwise the default agentic-coding topic is used."
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
if [ -z "$_HC" ]; then
  echo "HEADER_INSTALL: missing"
  echo "HEADER_NOTICE: full install required — run: npx skills add Header-inc/Header-skill -g  (or)  curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh"
else
  echo "HEADER_INSTALL: ok"
  echo "HEADER_BIN: $_HC"
  _HH="${HEADER_HOME:-$HOME/.header}"
  mkdir -p "$_HH"
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

If `HEADER_INSTALL: missing` was echoed, print the `HEADER_NOTICE` line to the user and **stop**. The audit requires `bin/header-audit`; there is no fallback flow. Tell them to re-run after the install completes.

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
| `HEADER_DEFAULT_TOPIC` | `1991163f-be9c-4df2-a33c-046a4d1357e1` (Self Improving Agent) | Topic UUID used when no argument, repo binding, or team topic applies. |
| `HEADER_STALENESS_DAYS` | `7` | Maximum briefing age in days before the audit flags the enrichment briefing as stale. |
| `HEADER_TEAM_DIR` | git toplevel, else `$PWD` | Directory whose `.header/config` is read as the team layer. Override mainly for testing. |

## Default flow: audit + enrichment

Every invocation runs this flow. The audit is local and read-only; the briefing is fetched from Header for enrichment.

> **Mode routing:** the audit always runs. A short word at the end of the invocation switches **what gets shown**, not what gets done: `summary` → render only the briefing's `summary` field, no audit output; `sources` → only `source_articles`, no audit output; `add-source <url>` → see "Add a source"; `since-last` → see "Since-last digest"; `cost` → see "Cost analytics". Anything else (a topic name/UUID/briefing URL, or no argument) runs the full audit-led flow below.

### Step 0 — Resolve the topic

The topic determines which briefing is pulled in for enrichment. Fallback chain (first match wins):

1. **Explicit argument** — if the user passed an identifier:
   - URL containing `/briefings/<uuid>` → extract the UUID, treat as a **briefing ID**, skip Step 1, go straight to Step 2 with `/api/v2/public/briefings/<uuid>`.
   - URL containing `/topics/<uuid>` or a bare UUID → use as the **topic ID** and proceed to Step 1.
   - Anything else → search `/api/v2/topics/public/catalog` for a case-insensitive substring match on `name`. One match → use its `id`; multiple → ask to disambiguate; none → fall through.
2. **Personal binding for this repo** — if `REPO_TOPIC` is non-empty **and** `HAS_KEY: yes`, use it (it wins over `TEAM_TOPIC`). Bound topics are private — use the authenticated endpoints, and run the session-start freshness check (see "Bound repos — freshness & schedule"). If `REPO_TOPIC` is set but no key is available, skip and fall through. A `404` means the topic was deleted server-side — offer `header-repo clear` and fall through.
3. **Team topic for this repo** — if `TEAM_TOPIC` is non-empty **and** `HAS_KEY: yes`, use it via the authenticated endpoints (same freshness check). Without a key, tell the user this repo pins a team topic that needs an API key (offer to sign up), then fall through. On `404` tell the user to fix `.header/config` (never auto-edit a committed file) and fall through.
4. **Resolved default topic** — `DEFAULT_TOPIC` if non-empty.
5. **Hardcoded default** → `1991163f-be9c-4df2-a33c-046a4d1357e1` (Self Improving Agent).

**Claude Code only:** the explicit argument is delivered as `$ARGUMENTS` when invoked via `/header <topic>`. Other harnesses: extract the topic identifier from the user's message text.

### Step 1 — Get the latest briefing ID

*Skip if Step 0 resolved a briefing ID directly.*

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

### Step 3 — Run the audit

Local, read-only — nothing leaves the machine. Run **both** scans. `<AUDIT>` is `header-audit`, in the same `bin/` dir as the preamble's `HEADER_BIN`.

```bash
<AUDIT> harness          # CLAUDE.md / AGENTS.md / settings / commands / subagents / MCP / Bash posture
<AUDIT> deps             # ecosystems / tool versions / install-cooldown gate
```

What the scans emit — and how to read each line — is documented under **"What the audit scans"** below. Capture the output and the line types (`FILE`, `MODEL`, `HIT`, `SECURITY`, `ECOSYSTEM`, `TOOL`, `GATE`); you'll join them with the briefing in the next step.

### Step 4 — Cross-reference and present

The audit's findings + the briefing's items become **one ranked recommendation list**.

**Recent activity (diff-aware):** glance at recently-touched files (`git log --name-only --pretty=format: -15 2>/dev/null | sort -u`) and recent commit subjects (`git log --oneline -15 2>/dev/null`). Weight recommendations toward areas with recent activity — a briefing item or audit hit that touches code the user changed this week is more actionable than one about a dormant corner. Name the connection when you surface it.

Build the unified list by combining:

- **Audit findings** — every `HIT` (prompt-debt pattern), `FILE` size signal (heavy always-loaded `CLAUDE.md`/`AGENTS.md`), `MODEL` mismatch, `SECURITY` posture, and `GATE absent` from `header-audit`.
- **Briefing-derived recommendations** — items in the briefing's `key_developments` or `summary` that touch the project's stack/tooling (read package manifests, lockfiles, language version files, build/test/CI configs, container/infra definitions, agent/skill definitions, `CLAUDE.md`, README), or that name a pattern the project doesn't yet use (or uses a now-legacy version of). The bias is toward **deletion** and toward changes the briefing endorses on the model currently configured.
- **Known issues** — themes from learnings/post-mortems/runbooks/architecture-decision-records/incident reports + a quick `TODO`/`FIXME`/`HACK` density scan. A recommendation that addresses a known issue jumps the queue.

When a `MODEL` is known, cross-reference its model card / release notes before declaring a prompt-debt `HIT` actionable — confirm the pattern is *still* debt on that model. Prefer briefing sources for the cross-reference; fall back to the web.

**Present** as a one-line scorecard, then a ranked recommendation list. Each recommendation is a hypothesis: **what** (the change), **where** (file + line/manifest), **why** (cite the audit line *or* the briefing item — link the `source_articles` URL for the latter), and the **expected effect** (`est.` and directional unless measured). Split into two groups:

- **Apply now** — deletions/simplifications, supply-chain gate, security patches. Low-risk and deterministic. On the user's yes, make the edit (show a diff first; for the gate, write/append the `<AUDIT> gate ...` snippet to `.npmrc`).
- **`[Experiment · coming soon]`** _(beta)_ — anything whose payoff must be *proven*: a model change, a major dependency/framework upgrade, a behavioral rewrite. State the A/B that *would* settle it ("A = current, B = proposed; measure tokens + test pass-rate over N runs"), label it not-yet-supported, and offer to **note the user's interest** so they're told when it ships. Run nothing.

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

**Caching within a session:** hold the `briefing_id` + `generated_at` + the audit output in conversation context. On re-invocation in the same session, reuse it unless the user says "refresh", "latest", "new", or "re-audit".

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
<LEDGER> record wanted    "<key>"    # an [Experiment · coming soon] the user wants
```

All ledger writes are best-effort, local-only, and never block the audit.

### Usage logging (run last in the audit flow)

After the audit + recommendations are delivered, log one usage event. `<TELEMETRY>` is `header-telemetry`, in the same `bin/` dir:

```bash
<TELEMETRY> log skill_run --outcome "<success|error>" --path "audit" --recs-surfaced <N> --recs-applied <N>
date -u +%Y-%m-%dT%H:%M:%SZ > "${HEADER_HOME:-$HOME/.header}/.last-run" 2>/dev/null || true
```

Records nothing unless the user opted into telemetry; only sends usage metadata — never workspace content. Best-effort.

### Fallback

If the default topic returns 404, browse the public catalog and pick a relevant topic:

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

- `FILE <path> <bytes> <est_tokens>` — every harness file found (`CLAUDE.md`, `AGENTS.md`, settings, commands, subagents, MCP config). `est_tokens` is `bytes/4`. Sum the always-loaded ones — that cost is paid on **every turn**.
- `MODEL <value>` — the model declared in settings, if any.
- `HIT <path> <lineno> <pattern_id> <excerpt>` — a known cargo-cult pattern. Run `<AUDIT> patterns` to list the ids and why each is debt.
- `SECURITY bash <level> <file>` (+ `SECURITY-DETAIL allow|deny <pattern>`) — Bash-tool permission posture from Claude Code settings:
  - `bypass` → **no permission gating** (`defaultMode: bypassPermissions`). Highest risk; if the agent can reach any production asset, recommend a command allow-list.
  - `denylist` → blacklist, which is bypassable (an agent can script around a blocked command) — recommend an allow-list.
  - `allowlist` → whitelist-leaning; affirm it, suggest tightening only if gaps.
  - **no `SECURITY` line** → no explicit policy (interactive prompts only). Fine for local dev; recommend an allow-list anywhere the agent reaches production.

Curate the hits — don't surface them blindly. When `MODEL` is known, cross-reference its model card / release notes to confirm the pattern is **still** debt on that model.

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
- **Outdated / vulnerable deps.** Run the ecosystem's own tools (`npm outdated`, `npm audit`, `pip list --outdated`). Security patches → apply now. Major upgrades → `[Experiment · coming soon]`.

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

**Where the spend is.** `report` ranks models by cost — surface the biggest line and name the obvious lever.

**No projections — name the lever, don't guess the saving.** A price re-rating of the same tokens is a guess. `"<COST>" savings` exists only to point at the experiment loop:

```
Header experiments are coming soon — A/B-test models in your own repo and verify
correctness before Header surfaces a recommendation.
```

Other subcommands: `"<COST>" refresh [--url U]`, `"<COST>" prices`, `"<COST>" cost <model> <in> <out> [cache_read] [cache_write_5m] [cache_write_1h]`. Add `--json` for machine output.

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

**Team-relevant settings only.** Because the file is committed, only the allow-list is honored: `default_topic`, `staleness_days`, `schedule_frequency_days`, `language`. Personal preferences and **anything consent- or code-related** (`telemetry`, `auto_update`, `auto_tune`, `update_check`) are **ignored** by design — `header-config team-show` makes its effective contents auditable.

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
