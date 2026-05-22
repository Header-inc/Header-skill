---
name: header-briefing
version: 0.5.2
description: "Browse and read Header intelligence briefings. Default: fetch the latest agentic coding briefing and surface suggestions relevant to this project. Supports public access (no auth) and authenticated workflows (API key)."
when_to_use: "Use when the user asks what's new in agents/MCP/coding tools, any new patterns to adopt, or invokes /header-briefing. Pass a topic name or UUID as the argument to fetch a specific topic; otherwise the default agentic-coding briefing is used."
argument-hint: "[topic-name-or-uuid-or-briefing-url]"
allowed-tools: Bash, AskUserQuestion
---

*The `when_to_use`, `argument-hint`, and `allowed-tools` frontmatter fields are honored by Claude Code; other harnesses ignore them safely.*

# Header Briefing Reader

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources. This skill fetches briefings and analyzes them for relevance to the current project. The default workflow requires no authentication.

> This skill uses `curl` so it runs in any agent with shell access (Claude Code, Cursor, Aider, OpenAI Codex CLI, Goose, etc.). Claude Code users may substitute `WebFetch` for the read-only GETs if they prefer.

## Preamble (run first)

Run this block before anything else. **Claude Code substitutes `{SKILL_DIR}`** with the absolute path of the directory containing this `SKILL.md` (the skill's base directory, provided on invocation). Other agents: replace `{SKILL_DIR}` with the path of the folder you loaded this file from. If you cannot determine it, leave the token — the fallback paths and the classic-mode floor below handle it.

```bash
# --- Header skill preamble - run before anything else ---
_HC=""
for _d in "{SKILL_DIR}" "$HOME/.claude/skills/header-briefing" \
          ".claude/skills/header-briefing" "$HOME/.codex/skills/header-briefing" \
          ".agents/skills/header-briefing"; do
  [ -x "$_d/bin/header-config" ] && { _HC="$_d/bin/header-config"; break; }
done
if [ -z "$_HC" ]; then
  echo "HEADER_MODE: classic"
  echo "HEADER_NOTICE: classic mode - bin/header-config not found; reinstall the full header-briefing/ folder for config + onboarding"
else
  echo "HEADER_MODE: enterprise"
  echo "HEADER_BIN: $_HC"
  _HH="${HEADER_HOME:-$HOME/.header}"
  mkdir -p "$_HH"
  if [ -n "${CI:-}" ] || [ -n "${HEADER_NONINTERACTIVE:-}" ]; then
    echo "INTERACTIVE: no"
  else
    echo "INTERACTIVE: yes"
  fi
  echo "DEFAULT_TOPIC: ${HEADER_DEFAULT_TOPIC:-$("$_HC" get default_topic)}"
  echo "REPO_TOPIC: $("$(dirname "$_HC")/header-repo" get 2>/dev/null || true)"
  echo "LANGUAGE: ${HEADER_LANGUAGE:-$("$_HC" get language)}"
  echo "STALENESS_DAYS: ${HEADER_STALENESS_DAYS:-$("$_HC" get staleness_days)}"
  echo "WELCOME_SEEN: $([ -f "$_HH/.welcome-seen" ] && echo yes || echo no)"
  echo "LANGUAGE_PROMPTED: $([ -f "$_HH/.language-prompted" ] && echo yes || echo no)"
  echo "SIGNUP_STATE: $(cat "$_HH/.signup-state" 2>/dev/null || echo unset)"
  echo "TELEMETRY_PROMPTED: $([ -f "$_HH/.telemetry-prompted" ] && echo yes || echo no)"
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

The block prints either `HEADER_MODE: classic` or `HEADER_MODE: enterprise`.

**Classic mode** — `bin/header-config` was not found. Run the briefing workflow below exactly as written, and skip every Preamble-dependent behavior (the first-run welcome and the signup funnel). If a `HEADER_NOTICE:` line was printed, show it to the user once so they know a fuller install is available.

**Enterprise mode** — use the echoed values for the rest of the session:

| Echoed line | Use |
|---|---|
| `HEADER_BIN` | Absolute path to `bin/header-config`. Re-substitute it in any later bash call that needs the config CLI — each `Bash` invocation is a fresh shell, so this echo is the simplest way to locate the helper again. |
| `DEFAULT_TOPIC` | Topic UUID for Step 0. Already resolves env var → config file → empty. |
| `REPO_TOPIC` | Topic UUID this repository is bound to (a custom topic the user created here), or empty. When non-empty **and** a key is available, it wins over `DEFAULT_TOPIC` in Step 0 — see "Bound repos — freshness & schedule". Empty → not a bound repo (or `repo_memory` is off). |
| `LANGUAGE` | Render user-facing output in this language. Already resolves env → config → `English`. |
| `STALENESS_DAYS` | Threshold for the briefing-age check in Step 2. |
| `INTERACTIVE` | `no` → scheduled / non-interactive run: skip the welcome, the language prompt, and the signup funnel. `yes` → all three are eligible. |
| `WELCOME_SEEN` | `no` (with `INTERACTIVE: yes`) → show the first-run welcome. |
| `LANGUAGE_PROMPTED` | `no` (with `INTERACTIVE: yes` and `LANGUAGE: English`) → show the first-run language prompt. |
| `SIGNUP_STATE` / `HAS_KEY` | Drive the signup funnel — see "First-run onboarding". |
| `TELEMETRY_PROMPTED` | `no` (with `INTERACTIVE: yes`, once the signup funnel is resolved) → ask telemetry consent once — see "Telemetry consent". |
| `UPDATE_CHECK` | `UPDATE_AVAILABLE old new` or `UPDATE_REQUIRED old min` → run the update flow (see "Staying up to date"). Absent when up to date, snoozed, or disabled. |

The echoed `DEFAULT_TOPIC` / `LANGUAGE` / `STALENESS_DAYS` already fold in the precedence **env var > `~/.header/config` > built-in default** — use them directly rather than re-reading env vars or the config file later.

## First-run onboarding

Runs **only in enterprise mode with `INTERACTIVE: yes`**. In classic mode, or on a scheduled / non-interactive run (`INTERACTIVE: no`), skip this whole section — print nothing, ask nothing.

**Claude Code only:** the choice below uses the `AskUserQuestion` tool. Other harnesses present the same options as a numbered list and ask the user to reply with a number.

### Welcome — before the briefing

If `WELCOME_SEEN: no`, print this once, then continue to Step 0:

> 👋 **Header** — I read what's new in agentic coding and check it against your project. I can also audit your agent's *own* setup — `CLAUDE.md`, model choice, dependencies — to cut token cost and catch supply-chain risk. No account needed to start.

```bash
touch "${HEADER_HOME:-$HOME/.header}/.welcome-seen"
```

If `WELCOME_SEEN: yes`, skip the welcome.

### Language — before the briefing

If the preamble echoed `LANGUAGE: English` (the built-in default) **and** `LANGUAGE_PROMPTED: no`, ask **once** before Step 0 which language to render briefings in. If `LANGUAGE` echoed anything other than `English`, the user has already declared a preference (env var or config) — skip the prompt, but still touch the marker so it never fires later.

Ask:

> **Which language should briefings be rendered in?**
>
> Briefing content stays English on the wire; the agent translates the presentation for you. Translation quality varies by language; proper nouns, code identifiers, and URLs stay verbatim.

Options (label English as recommended — it's the default):

1. **English** — recommended, keep as default. No translation.
2. **Spanish** — agent translates the presentation.
3. **Turkish** — agent translates the presentation.
4. **Other** — ask the user which language to use.

After the user picks, persist the choice and touch the marker. The preamble echoed `HEADER_BIN: <path>` — substitute that path; each Bash call is a fresh shell so the env-var trick from the preamble doesn't carry over:

```bash
<HEADER_BIN> set language "Chosen"
touch "${HEADER_HOME:-$HOME/.header}/.language-prompted"
```

Replace `Chosen` with the user's pick (`English`, `Spanish`, `Turkish`, or the free-form name they typed). Persisting `English` explicitly is harmless — feel free to do it or skip the `set`. Always touch the marker so the prompt never fires again.

Skip the prompt entirely if `INTERACTIVE: no` or `LANGUAGE_PROMPTED: yes`.

### Audit offer — after the briefing

The audit (see "Audit (beta)") is the free, no-account hook and the clearest taste of where Header is heading — so **introduce it proactively; don't wait for the user to ask.** Run this **once** (first applicable run), after the briefing, when `INTERACTIVE: yes` and no `~/.header/.audit-offered` marker exists. Touch the marker either way so it never repeats — this is also how existing users discover the audit on their next run.

> Beyond the news: Header's larger aim is to **optimize the coding agent itself** — cut token cost, raise reliability, and *(soon)* **prove** changes with experiments. As a first step I can audit your agent's own setup — `CLAUDE.md`, model choice, dependencies — for prompt-config debt and supply-chain gaps. Free, no account, all local. Run it now?

```bash
touch "${HEADER_HOME:-$HOME/.header}/.audit-offered"
```

On **yes**, run the "Audit (beta)" flow now; its findings lead naturally into the account CTA (tailored briefings now, experiments when they land) — if the user signs up from there, go to "Save the key" and skip re-asking below. On **no**, continue to the signup funnel. Either way, the user can run `/header-briefing audit` anytime. Skip in classic mode and when `INTERACTIVE: no`.

### Signup funnel — after the briefing

Run this **after the briefing has been delivered** (end of Step 4), so value lands before any pitch. Trigger only when `HAS_KEY: no` **and** `SIGNUP_STATE` is `unset` or `pending` (if `done` or `public-only`, skip). It also runs at this point if the user asks for an auth-only feature (a custom topic / on-demand generation) without a key.

Lead with the value the user already got — the public flow is genuinely useful — then offer the upgrade. Don't imply the briefing was generic-and-useless:

> The recommendations above came with no account: the briefing itself is Header's **general** agentic-coding briefing (the same sources for everyone), but I analyzed *this* repo locally and surfaced only what applies to your stack and open issues.
>
> A **custom topic** goes further — it tailors the briefing's **sources and focus** to your project from the start, so the raw material is about your stack instead of a shared feed filtered after the fact. That needs a free Header account (free trial, no credit card).
>
> Where are you?
> 1. **New to Header** — walk me through a 30-second signup
> 2. **I have an account** — point me to my API key
> 3. **Just public briefings** — no account, don't ask again

**1 — New to Header.** Offer the signup link and to open it:

> Sign up and start the free trial at https://joinheader.com/ — about 30 seconds, no card.

```bash
URL="https://joinheader.com/"
if   command -v open     >/dev/null 2>&1; then open "$URL"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
elif command -v start    >/dev/null 2>&1; then start "$URL"
else echo "Open $URL in your browser."
fi
```

Then walk them through: create the account → the free trial starts automatically → open **Settings ▸ API Keys** → create a key with **read + write** access (`hdr_sk_...`; write is required to create custom topics) → paste it here. Go to **Save the key**.

**2 — I have an account.** Point them at **Settings ▸ API Keys** on https://joinheader.com/, ask them to create a key with **read + write** access (write is required to create custom topics) and paste it here. Go to **Save the key**.

**3 — Just public briefings.** Record it and don't ask again:

```bash
printf 'public-only\n' > "${HEADER_HOME:-$HOME/.header}/.signup-state"
```

Tell them public briefings keep working with no account; they can re-run the funnel later by deleting `~/.header/.signup-state`.

**Deferred (picked 1 or 2 but no key pasted now).** Record `pending`:

```bash
printf 'pending\n' > "${HEADER_HOME:-$HOME/.header}/.signup-state"
```

On a later run with `SIGNUP_STATE: pending`, re-offer the funnel **once** more; if the user defers again, write `public-only` so it stops nagging.

### Save the key

When the user pastes a key, offer to save it:

> Save it to `~/.header/credentials` (readable only by you) so you don't re-enter it each session?

If yes — write it under a tight umask, confirm the file is private, and fall back to a manual `export` if the filesystem can't secure it. Replace `PASTED_KEY` with the key the user pasted:

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

If the user declines saving, tell them to `export HEADER_API_KEY=...` in their shell profile, and record `done` (they have a key for this session):

```bash
printf 'done\n' > "${HEADER_HOME:-$HOME/.header}/.signup-state"
```

The credentials file is **only ever read as data** — the preamble and the authenticated `curl` calls parse the `HEADER_API_KEY=` line with `grep`/`sed`. Nothing sources or executes it.

### First-run handoff — build the repo-tailored topic now

When the funnel just produced a usable key (`SIGNUP_STATE` is now `done`) and you're still `INTERACTIVE: yes`, **don't stop at "ready."** Continue, in this same session, straight into **"Auto-create a topic from your project"** (below) — this is the whole reason the user signed up, so close the loop now instead of waiting for the next run:

> Now let me make a briefing that's actually about **this repo** — tailored to <one-line summary of the detected stack and priorities>, not the shared feed. Sound good?

This prompt stands in for Auto-create's own offer — don't ask twice. On yes, run the Auto-create *steps*: draft the goal from the Step 3 audit, create the topic, then **offer to remember it for this repo and offer a schedule** (see "Remember the topic for this repo" and "Bound repos — freshness & schedule"). That ends the first run with a briefing that's tailored, bound to the repo, and (optionally) auto-refreshing.

The key was added mid-session, so the preamble's `HAS_KEY: no` echo is stale — proceed anyway; the authenticated `curl` calls resolve the key from the credentials file you just wrote. The `.topic-offered` marker still gates Auto-create, so this won't double-ask on later runs.

### Telemetry consent

Ask **once**, only when `INTERACTIVE: yes`, `TELEMETRY_PROMPTED: no`, and the signup funnel is already resolved (`SIGNUP_STATE` is `done` or `public-only`) — so it lands a session or two after first contact, not piled onto the first run. Skip in classic mode.

Ask (`AskUserQuestion` on Claude Code; numbered plain text elsewhere):

> Help improve the Header skill? It can share **usage only** — which path ran, the outcome, and how many recommendations you applied. **Never** your code, file paths, repo names, or briefing content.
>
> 1. **Share usage** (recommended) — includes a random install id, not tied to your identity
> 2. **Anonymous only** — aggregate counts, no id
> 3. **No thanks**

Map the choice and record that you asked (`<HEADER_BIN>` is the preamble's echoed path):

```bash
<HEADER_BIN> set telemetry full        # "Share usage"   (or: anonymous / off)
touch "${HEADER_HOME:-$HOME/.header}/.telemetry-prompted"
```

Telemetry stays off until the user opts in here; they can change it any time with `header-config set telemetry off|anonymous|full`.

## Staying up to date

Driven by the preamble's `UPDATE_CHECK` line. Handle it **right after the preamble, before the briefing** — an out-of-date skill may not work against the API. If there was no `UPDATE_CHECK` line, skip this section. Both branches use `<HEADER_BIN>` (the path the preamble echoed as `HEADER_BIN:`).

### UPDATE_REQUIRED — non-optional

`UPDATE_CHECK: UPDATE_REQUIRED <old> <min>` means the installed skill is older than the minimum version the Header API still supports; briefings may fail until it's updated.

- **Interactive** (`INTERACTIVE: yes`): tell the user plainly and offer to update now — go to **Run the update**. If they decline, warn that briefings may fail, then continue.
- **Non-interactive** (`INTERACTIVE: no`): do not prompt. Print one warning line ("Header skill v{old} is below the supported minimum v{min} — update soon") and continue. Never block a scheduled run.

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
- **Not now** → write an escalating snooze (next reminder: level 1 = 24h, 2 = 48h, 3+ = 1 week) and continue without mentioning it again:

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

1. Read "what's new" from the cached release info (both fields optional):

```bash
cat "${HEADER_HOME:-$HOME/.header}/version-info.json" 2>/dev/null
```

2. Re-run the installer — it fetches the latest, swaps the install atomically, and rolls back on failure:

```bash
curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
```

(Working from a git clone? `git pull --ff-only && ./install.sh` instead. A project-local copy updates by re-copying the `header-briefing/` folder.)

3. Clear the update cache so the next run re-checks cleanly:

```bash
rm -f "${HEADER_HOME:-$HOME/.header}/last-update-check" "${HEADER_HOME:-$HOME/.header}/update-snoozed"
```

4. Tell the user "Updated to v{new}" plus the `message` (and `notes_url` if present), then continue with the briefing. If the installer reported a failure it restored the previous version — say so and suggest retrying.

The update takes effect on the **next** `/header-briefing` — the current session keeps the already-loaded `SKILL.md` in context until then.

## Configuration

All configuration is via environment variables. None are required for the default public-briefing flow.

| Variable | Default | Description |
|---|---|---|
| `HEADER_API_KEY` | — | API key (`hdr_sk_...`) for authenticated workflows (custom topics, on-demand generation). |
| `HEADER_LANGUAGE` _(Beta)_ | `English` | Language for output rendering. API content stays English; the agent translates the presentation. Set to `Turkish`, `Spanish`, etc. **Beta:** translation quality varies by language; proper nouns, identifiers, and URLs are kept verbatim. Report issues at [joinheader.com](https://joinheader.com). |
| `HEADER_DEFAULT_TOPIC` | `1991163f-be9c-4df2-a33c-046a4d1357e1` (Self Improving Agent) | Topic UUID used when no argument is passed. |
| `HEADER_STALENESS_DAYS` | `7` | Maximum briefing age in days before warning the user the content may be stale. |

## Default: Agentic Coding Briefing

Fetch the latest briefing for the resolved topic (default: "Self Improving Agent") and check for suggestions relevant to this project.

> **Mode routing:** if the user invokes `/header-briefing audit` (or says "audit my setup / agent / harness / dependencies"), run the **"Audit (beta)"** section instead of the briefing flow below. `add-source <url>` routes to "Add a source". Anything else (a topic name/UUID/URL, or nothing) runs the briefing flow here.

### Step 0 — Resolve the topic

Determine the topic UUID using this fallback chain (first match wins):

1. **Explicit argument** — if the user passed an identifier:
   - URL containing `/briefings/<uuid>` (e.g., `https://joinheader.com/briefings/<uuid>`) → extract the UUID, treat it as a **briefing ID**, skip Step 1 entirely, and go straight to Step 2 (`/api/v2/public/briefings/<uuid>`).
   - URL containing `/topics/<uuid>` or a bare UUID → use as the **topic ID** and proceed to Step 1.
   - Anything else → search `/api/v2/topics/public/catalog` for a case-insensitive substring match on `name`. If exactly one matches, use its `id`. If multiple match, ask the user to disambiguate. If none match, fall through.
2. **Remembered topic for this repo** — in enterprise mode, if the preamble echoed a non-empty `REPO_TOPIC` **and** a key is available (`HAS_KEY: yes`), use it. This is a custom topic the user bound to this repository, so it is private: fetch it via the **authenticated** endpoints, and run the session-start freshness check first — see "Bound repos — freshness & schedule". If `REPO_TOPIC` is set but no key is available (key was removed), skip it and fall through. A `404` on fetch means the topic was deleted server-side — treat the binding as stale (offer `header-repo clear`) and fall through.
3. **Resolved default topic** — in enterprise mode, use the preamble's `DEFAULT_TOPIC` value when it is non-empty (it already reflects the `HEADER_DEFAULT_TOPIC` env var, then `~/.header/config`). In classic mode, use the `HEADER_DEFAULT_TOPIC` env var directly.
4. **Hardcoded default** → `1991163f-be9c-4df2-a33c-046a4d1357e1` (Self Improving Agent).

**Claude Code only:** the explicit argument is delivered as `$ARGUMENTS` when invoked via `/header-briefing <topic>`. Other harnesses: extract the topic identifier from the user's message text.

### Step 1 — Get the latest briefing ID

*Skip this step if Step 0 resolved a briefing ID directly (i.e., a `/briefings/<uuid>` URL was passed) — go straight to Step 2 with that ID.*

```bash
curl -sS --retry 1 -w "\n%{http_code}" \
  https://joinheader.com/api/v2/topics/public/{topic_id}
```

Extract the `latest_briefing.id` from the JSON response — this is the briefing ID for Step 2.

### Step 2 — Fetch the full briefing

```bash
curl -sS --retry 1 -w "\n%{http_code}" \
  https://joinheader.com/api/v2/public/briefings/{briefing_id}
```

From the JSON response, pull out: `summary`, `key_developments`, `source_articles` (title and url for each), and `generated_at`.

Note: `key_developments` is a JSON-encoded string — parse it from the string into a structured list.

**Staleness check:** Compare `generated_at` against the current date. If the difference exceeds `${HEADER_STALENESS_DAYS:-7}` days, prepend a one-line warning to the output (e.g., "⚠ This briefing is 12 days old — the latest developments may not be reflected"). With an API key, suggest re-triggering generation via `POST /api/v2/goals/{goal_id}/briefings` (see Custom Briefings).

### Error handling

Apply to every Header API call. Don't auto-retry blindly; inform the user before retrying.

| Condition | Action |
|---|---|
| Network failure / DNS / timeout | The `--retry 1` already handles transient blips. If the second attempt fails, tell the user the API is unreachable and stop. |
| HTTP `429` Too Many Requests | Read the `Retry-After` response header. Wait that many seconds (or 30s if absent), then retry once. If still 429, tell the user and stop. |
| HTTP `4xx` (other) | Surface the JSON `detail` or `error.message` field to the user. Do not retry. |
| HTTP `5xx` | Retry once after 5s. If it fails again, tell the user the Header API is having issues. |
| Empty body or malformed JSON | Tell the user the response was unparseable; suggest the catalog fallback below. |
| Briefing `status: FAILED` | Don't auto-retry. Tell the user the briefing failed; if they have an API key, suggest re-triggering via `POST /api/v2/goals/{goal_id}/briefings` (Custom Briefings). |

### Step 3 — Audit the workspace and analyze relevance

The audit happens locally — no project data is sent to Header. The shape of the audit is fixed; the inputs vary by project. Use your normal repo-exploration tools (directory listings, file reads) to find relevant artifacts; do not rely on a hardcoded file list.

**Recent activity (diff-aware):** before building the audit, glance at what the project has been working on lately — recently-touched files (`git log --name-only --pretty=format: -15 2>/dev/null | sort -u`) and recent commit subjects (`git log --oneline -15 2>/dev/null`). Weight recommendations toward areas with recent activity: a briefing item that touches code the user changed this week is far more actionable than one about a dormant corner. Name the connection when you surface it ("you just added a retrieval pipeline — this chunking technique applies directly"). In a non-git project, skip this and weight by the stack instead.

1. **Identify the project's stack and tooling** from whatever metadata the project happens to use — package manifests, lockfiles, language version files, build/test/CI configs, container or infrastructure definitions, agent/skill definitions. Read `CLAUDE.md` and the project README if present for stated context and conventions.

2. **Find what the team already knows is broken, missing, or pending.** Look for learnings, post-mortems, runbooks, retrospectives, architecture/decision records, changelogs, roadmaps, backlogs/TODO docs, and incident reports — at the repo root and in any conventional documentation directory. Also do a quick scan for in-code `TODO`/`FIXME`/`HACK` markers as a density signal. Cite source files when you reference an item.

3. **Build the audit summary.** This is the structured input to Step 4 — its job is to make the comparison between the briefing's content and the project's actual state explicit, so recommendations are grounded in observed reality rather than generic best-practice. Populate each row with items relevant to the briefing topic, not an exhaustive inventory:

   - **Stack** — languages, frameworks, runtime versions. The topic-relevance filter: items here scope which parts of the briefing apply at all (a React pattern doesn't help a Go shop).
   - **Tooling** — package manager, build/test/CI tooling, agent-related deps (MCP servers, AI SDKs, etc.). The layer where briefings about new tools, runners, and workflows usually land.
   - **Known issues / pain points** — themes drawn from step 2; group similar items and cite the source file. The highest-leverage row: a briefing item that addresses a named pain point jumps the queue in step 4.
   - **Mentioned in briefing** — items from the briefing's `key_developments` or `summary` that overlap anything in Stack, Tooling, or Known issues. The first-pass relevance filter.
   - **Gaps** — patterns the briefing endorses that this project doesn't yet use, including cases where the project's current approach is now considered legacy or superseded.

4. **Surface recommendations** drawn from **Mentioned in briefing**, **Gaps**, and especially anything that addresses an entry in **Known issues / pain points**. Prioritize the last group — the team has already named these as problems, so a briefing-backed remediation is more actionable than a greenfield suggestion. Each recommendation gets one sentence of rationale tying it to a specific item from the audit, citing the source file when it maps to a known issue. **Provenance:** link the `source_articles` URL behind each recommendation so the user can verify it before acting. In enterprise mode, also apply the recommendation ledger — assign each rec a key, skip ones already dismissed, and follow up on ones already applied (see "Recommendation ledger" below).

### Step 4 — Offer to implement

After presenting recommendations, ask the user which (if any) they'd like to implement. If the user selects one or more, proceed with implementation in the current project.

**Output format:** Detect modifiers in the user's invocation and adjust depth before presenting:

| User says | Show |
|---|---|
| "summary", "tl;dr", "short" | Just the briefing `summary` (no audit, no recommendations). |
| "key developments", "highlights" | The parsed `key_developments` list with one-line takes. |
| "sources", "links" | Just `source_articles` (title + url). |
| _none of the above_ (default) | Full output: summary + audit + recommendations. |

**Output language:** Render all user-facing output in `${HEADER_LANGUAGE:-English}`. Translate prose, headings, and rationale; keep proper nouns, ticker symbols, code identifiers, and URLs untouched. API request/response content remains English on the wire.

**Caching within a session:** After fetching a briefing, hold its `briefing_id` and `generated_at` in conversation context. If the skill is re-invoked for the same topic in the same session, reuse the cached briefing instead of re-fetching — unless the user says "refresh", "latest", "new", or asks for a fresh briefing.

**After the briefing is delivered** — in enterprise mode with `INTERACTIVE: yes`, run the post-briefing onboarding in order: the **audit offer**, then the **signup funnel** (see the "First-run onboarding" section above). Skip both in classic mode or on non-interactive runs.

### Recommendation ledger

In **enterprise mode**, record the user's disposition of each recommendation so future briefings adapt. Skip this whole block in classic mode or when `header-config get ledger` is `false`. `<LEDGER>` below is `header-ledger`, in the same `bin/` directory as the `HEADER_BIN` path the preamble echoed.

**While surfacing recommendations (Step 3):**
- Give each recommendation a short stable `key` (lowercase, hyphenated, e.g. `mcp-streaming`) — the same idea keeps the same key across briefings.
- `<LEDGER> status <key>` — if it returns `dismissed`, drop the recommendation (already declined). If `applied`, prefer a follow-up framing over re-recommending.
- `<LEDGER> list --action applied --since-days 30` — recently-adopted keys to proactively follow up on ("you adopted X — here's a new wrinkle").
- Record each recommendation you actually show:

```bash
<LEDGER> record surfaced "<key>" --title "<short title>" --briefing "<briefing_id>" --topic "<topic_id>" --source "<source_url>"
```

**After the user chooses (Step 4):** record the outcome for each —

```bash
<LEDGER> record applied   "<key>"    # implemented (or asked you to implement)
<LEDGER> record dismissed "<key>"    # explicitly rejected
<LEDGER> record snoozed   "<key>"    # "not now"
```

All ledger writes are best-effort, local-only, and never block the briefing — nothing leaves the machine.

### Usage logging (run last)

In enterprise mode, after delivering the briefing, log one usage event. `<TELEMETRY>` is `header-telemetry`, in the same `bin/` dir as the `HEADER_BIN` path the preamble echoed:

```bash
<TELEMETRY> log skill_run --outcome "<success|error>" --path "<default|catalog|custom>" --recs-surfaced <N> --recs-applied <N>
date -u +%Y-%m-%dT%H:%M:%SZ > "${HEADER_HOME:-$HOME/.header}/.last-run" 2>/dev/null || true
```

It records nothing unless the user opted into telemetry, and only ever sends usage metadata — never workspace content (see "Telemetry consent"). Best-effort; never block the briefing.

### Fallback

If the default topic returns 404, browse the public catalog to find a relevant topic:

```bash
curl -sS -w "\n%{http_code}" https://joinheader.com/api/v2/topics/public/catalog
```

Pick a topic from the returned list (each entry has `id`, `name`, `description`, `subscriber_count`) and use its `id` in place of the default topic ID above.

---

Want a briefing tailored to this specific project? Sign up at [joinheader.com](https://joinheader.com), create an API key, and use the **Custom Briefings** workflow below.

## Audit (beta)

> **Beta.** A local, no-account scan of your *agent harness* that finds debt and the changes worth proving. It does the deterministic half — find and fix obvious debt — for free; the rigorous half (proving a change with an A/B **experiment**) is **coming soon, not yet supported**. Don't fabricate experiment results or savings percentages; only state numbers the scan actually measured (and label estimates `est.`).

Triggered by `/header-briefing audit` or "audit my setup / harness / dependencies". Everything here reads **local files only — nothing leaves the machine.** This is also a strong no-account onboarding hook: it delivers specific value without a key. `<AUDIT>` is `header-audit`, `<LEDGER>` is `header-ledger`, `<TELEMETRY>` is `header-telemetry` — all in the same `bin/` dir as the `HEADER_BIN` path the preamble echoed. Skip the ledger/telemetry steps in classic mode.

It runs **two scans**:

### 1. Prompt / config debt (harness)

```bash
<AUDIT> harness          # add --repo DIR to target a specific repo
```

The premise (per *"prompts are technical debt too"*): harness instructions are written for a model and a moment, and they **rot silently** — workarounds for weaknesses newer models fixed, format-nagging, role puffery, all loaded every turn. The scan emits:

- `FILE <path> <bytes> <est_tokens>` — every harness file found (`CLAUDE.md`, `AGENTS.md`, settings, commands, subagents, MCP config). `est_tokens` is `bytes/4`, a rough proxy. Sum the always-loaded ones (`CLAUDE.md` + `AGENTS.md`) — that cost is paid on **every turn**.
- `MODEL <value>` — the model declared in settings, if any.
- `HIT <path> <lineno> <pattern_id> <excerpt>` — a known cargo-cult pattern. Run `<AUDIT> patterns` to see each id and why it's debt.
- `SECURITY bash <level> <file>` (+ `SECURITY-DETAIL allow|deny <pattern>`) — the Bash-tool permission posture from Claude Code settings. Surface it per the briefing's whitelist-over-blacklist insight:
  - `bypass` → **no permission gating** (`defaultMode: bypassPermissions`). Highest risk; if the agent can reach any production asset, recommend a command **allow-list**.
  - `denylist` → a blacklist, which is bypassable (an agent can write a script that sidesteps the blocked command) — recommend moving to an allow-list.
  - `allowlist` → whitelist-leaning; affirm it, suggest tightening only if there are gaps.
  - **no `SECURITY` line** → no explicit Bash policy (interactive prompts only); fine for local dev, but recommend an allow-list anywhere the agent can reach production.

Curate the hits — don't surface them blindly. When a `MODEL` is known, confirm the pattern is actually debt **on that model** by cross-referencing its model card / release notes (ideally via a Header source; otherwise the web). The bias is toward **deletion**: the cheapest, safest win is removing debt, and it's exactly what the source material recommends.

### 2. Dependency & supply-chain (deps)

```bash
<AUDIT> deps             # add --repo DIR to target a specific repo
```

Emits `ECOSYSTEM`, `TOOL` (with `ok|too-old|absent` vs the minimum that honors a cooldown gate), and `GATE` (`present|absent`) lines. Two things to surface:

- **Supply-chain cooldown gate.** If `GATE npm absent` or `GATE pip absent`, recommend a **min-release-age / install-cooldown** gate: refuse to install packages published in the last N days (default 7), so freshly-compromised releases (the chalk/debug, eslint-config-prettier class of incidents) are blocked until they're caught and pulled. This matters most where the install runs with secrets (a CI runner holding a deploy key) — a trojaned transitive dep otherwise has a direct path to them. Get the exact snippet to apply:

  ```bash
  <AUDIT> gate npm 7      # prints .npmrc content (min-release-age=7)
  <AUDIT> gate pip 7      # prints pip cooldown guidance (--uploaded-prior-to P7D)
  ```

  If `TOOL npm too-old` / `TOOL pip too-old`, note the gate is **silently ignored** until the tool is bumped (npm ≥ 11.10, pip ≥ 26.1) — locally **and in CI**, or it does nothing.
- **Outdated / vulnerable deps.** Run the ecosystem's own tools (`npm outdated`, `npm audit`, `pip list --outdated`) and interpret. Security patches → apply-now (after the gate is in place). Major upgrades → experiment (below).

### Present the scorecard, then the split

Lead with a one-line scorecard, then ranked findings. Each finding is a **hypothesis**: what, where (cite the line/manifest), why it's debt, the proposed change, and the expected effect (`est.` and directional unless measured). Split findings two ways:

- **Apply now** — deletions/simplifications, adding the supply-chain gate, security patches. Low-risk and deterministic. On the user's yes, make the edit (show a diff first; for the gate, write/append the `<AUDIT> gate ...` snippet to `.npmrc`). These need no experiment.
- **`[Experiment · coming soon]`** — anything whose payoff must be *proven*: a model change, a major dependency/framework upgrade, a behavioral rewrite. State the A/B that *would* settle it ("A = current, B = proposed; measure tokens + test pass-rate over N runs"), label it not-yet-supported, and offer to **note the user's interest** so they're told when it ships. Run nothing.

### Record findings (ledger + telemetry)

In enterprise mode, record each finding so demand and outcomes accrue — this is the corpus the experimentation platform will run on:

```bash
<LEDGER> record surfaced "<key>" --title "<short finding>" --topic audit   # each finding shown
<LEDGER> record applied  "<key>"                                           # user applied the fix
<LEDGER> record dismissed "<key>"                                          # user declined
<LEDGER> record wanted   "<key>"                                           # user wants the experiment
```

Then log usage + experiment demand (consent-gated; no-op when telemetry is off; **never** sends code, paths, or line content — only counts and kinds):

```bash
<TELEMETRY> log audit --path harness --recs-surfaced <findings> --recs-applied <applied>
<TELEMETRY> log experiment_interest --recs-surfaced <wanted_count>   # only if any were wanted
```

The local ledger always captures the full detail; telemetry aggregates the demand across users **only if** the user opted in.

## Browse Public Topics

List all public topics:

```bash
curl -s https://joinheader.com/api/v2/topics/public/catalog
```

Each entry in the response has `id`, `name`, `description`, and `subscriber_count`.

Get details for a specific topic (includes latest briefing summary):

```bash
curl -s https://joinheader.com/api/v2/topics/public/{topic_id}
```

The response includes the topic `name`, `description`, and `latest_briefing` details. Then fetch the full briefing using the `latest_briefing.id` via the public briefing endpoint (same as Default Step 2).

## Custom Briefings (API Key Required)

For users with a Header account. Create a custom topic with a goal tailored to your project, then generate briefings on demand.

### API key resolution

Every authenticated call in this section needs your API key. The key may be exported as `HEADER_API_KEY`, or saved (via the signup funnel) to `~/.header/credentials`. Because each shell starts fresh, run this **once at the start of any shell that makes an authenticated call**, before the `curl`:

```bash
[ -n "${HEADER_API_KEY:-}" ] || HEADER_API_KEY="$(sed -n 's/^HEADER_API_KEY=//p' "${HEADER_HOME:-$HOME/.header}/credentials" 2>/dev/null)"
export HEADER_API_KEY
```

Env var first, then the credentials file — which is **parsed, never sourced**. The `curl` examples below then use `$HEADER_API_KEY` directly. If it resolves empty, tell the user no key is configured and offer the signup funnel.

### Tier limits and error handling

Authenticated endpoints can return structured error codes when you hit a tier limit. Two suffixes, one per failure mode:

| Suffix | HTTP | Meaning | Recovery |
|---|---|---|---|
| `*_FREE` | 403 | The caller is on the free tier; the action is Pro-only. | Ask the user — start the free **trial** (only if the error response includes `can_start_trial: true`) or **upgrade** directly to Pro. **Never auto-pick a path.** On *trial* → `POST /api/v2/billing/trial/start`, then retry the original request. On *upgrade* → `POST /api/v2/billing/create-checkout`, parse the returned URL, open it (portable: `open` / `xdg-open` / `start`), and tell the user to finish checkout in the browser. |
| `*_QUOTA` | 429 | Paid tier but at the cap (e.g., 10 topics, 7 manual briefings per rolling 24 h). | Tell the user. Suggest: wait for the cap to reset, delete a topic to make room, or email `info@joinheader.com` if the use case justifies a higher cap (no higher public tier exists). |

**Concrete codes you may encounter:**

| Endpoint | Free-tier code | Paid-cap code |
|---|---|---|
| `POST /api/v2/topics/` | `TOPIC_LIMIT_FREE` | `TOPIC_LIMIT_QUOTA` |
| `POST /api/v2/goals/{id}/briefings` | `MANUAL_BRIEFING_FREE` | `MANUAL_BRIEFING_QUOTA` |
| `PUT /api/v2/topics/{id}` | `EDIT_FREE` | — |
| `PUT /api/v2/goals/{id}` | `EDIT_FREE` | — |

**`https://joinheader.com/docs` is the canonical source of current error codes and recovery flows.** When an error response carries a code that is not in the table above — or you want to confirm the recovery steps are still current — fetch the docs page and consult it. The table here is a snapshot:

```bash
curl -sS https://joinheader.com/docs
```

#### TOPIC_LIMIT_FREE — the most common one

When `POST /api/v2/topics/` returns `403` with `error.code: "TOPIC_LIMIT_FREE"`, the response also includes `can_start_trial`. Ask the user (`AskUserQuestion` on Claude Code, numbered plain text elsewhere):

> Custom topics need a Pro account, and you're on the free tier. Pick one:
>
> 1. **Start the free trial now** (recommended — no credit card needed)
> 2. Upgrade to Pro directly

If they pick the trial (and `can_start_trial: true`):

```bash
curl -sS -X POST https://joinheader.com/api/v2/billing/trial/start \
  -H "Authorization: Bearer $HEADER_API_KEY"
```

Then **retry the original `POST /api/v2/topics/` request** — it should now succeed. If they pick upgrade (or `can_start_trial: false`), kick off checkout and open the returned URL:

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

The same trial-vs-upgrade pattern applies to any `*_FREE` code (`MANUAL_BRIEFING_FREE`, `EDIT_FREE`, …) — when in doubt, curl the docs page above and follow its current recovery instructions.

### Setup

Create an API key with **read + write** access from **Settings > API Keys** at [joinheader.com](https://joinheader.com) — write is required to create custom topics:

```bash
export HEADER_API_KEY="hdr_sk_..."
```

### Create a custom topic

Before POSTing, **ask the user whether to include any custom sources** on top of the default source group:

> Add custom sources to this briefing topic? You can include additional RSS feeds, YouTube channels, Reddit subs, or existing Header source groups / source IDs alongside the default group (which covers AI agent frameworks, MCP, and coding tools).
>
> 1. **No, just the default sources** (recommended — covers AI agent frameworks, MCP, coding tools)
> 2. Yes — I'll provide them

If they say yes, collect from the user. Topics link **source groups**, not individual sources (the create body takes `source_group_ids`, min 1):

- Existing **source group IDs** → add to `source_group_ids` alongside the default.
- Individual **source IDs** or **new feed URLs** → put them in a group first (see "Add a source"), then include that group's id in `source_group_ids`. Or let Header propose a tailored group: `POST /api/v2/sources/recommend` (`topic_name`, `goal_description`) → `POST /api/v2/sources/recommend/commit` (returns a new `group_id`).

Then POST to the Header API to create the topic — with a default goal, auto-triggering the first briefing, and any extra `source_group_ids` the user provided in the JSON body:

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

The default source group (`64981a34-...`) covers AI agent frameworks, MCP, coding tools, and related sources. Tailor the `goal_description` based on the project's actual tech stack and current priorities.

The response includes `first_briefing_id` — generation runs asynchronously.

### Auto-create a topic from your project

When a key is present but the user has no custom topic yet (`INTERACTIVE: yes`, no `~/.header/.topic-offered` marker), offer to create one tailored to this repo — the Step 3 audit already inferred the stack, so draft the goal for them:

> Want briefings tuned to *this* project? I'll create a topic focused on <one-line summary of the detected stack and priorities> — no typing needed.

On yes, POST it (reuse "Create a custom topic", filling `goal_description` from the detected stack and any named pain points). For a sharper fit, first let Header propose sources for that goal — `POST /api/v2/sources/recommend` → `POST /api/v2/sources/recommend/commit` returns a `group_id` to create the topic with. On a `TOPIC_LIMIT_FREE` response, run the trial/upgrade flow ("Tier limits and error handling"). Always `touch "${HEADER_HOME:-$HOME/.header}/.topic-offered"` so it asks only once.

### Remember the topic for this repo

Right after a topic is created — whether via "Create a custom topic" or "Auto-create" — in **enterprise mode** with `INTERACTIVE: yes`, offer to bind it to the current repository so future sessions here reuse it automatically. Offer; don't write silently.

> Remember this topic for **this repo**? New `/header-briefing` runs here will use it instead of the public default. (Stored locally in `~/.header/repos.jsonl` — never inside your repo, never sent.)

On yes, record the binding. `<REPO>` is `header-repo`, in the same `bin/` dir as the `HEADER_BIN` path the preamble echoed:

```bash
"<REPO>" bind <new_topic_id> "<topic name>"
```

The next session's preamble echoes it as `REPO_TOPIC`, and Step 0 picks it up above the global default. Then immediately offer a schedule (next section). To forget it later, run `header-repo clear` from inside the repo.

### Bound repos — freshness & schedule

This runs at session start **only** when the preamble echoed a non-empty `REPO_TOPIC` and a key is available (`HAS_KEY: yes`). It replaces the public Step 1 fetch for bound repos: the bound topic is private, so use the authenticated endpoints. `<REPO>` is `header-repo`; `_HK` is the resolved key (env var or `~/.header/credentials`, as in the other authenticated calls).

**1. Fetch the bound topic and check freshness.**

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $_HK" \
  https://joinheader.com/api/v2/topics/{REPO_TOPIC}
```

- `404` → the topic was deleted server-side. Tell the user, run `"<REPO>" clear`, and fall back to the default topic (Step 0 step 3).
- Otherwise read `default_goal_id` and `latest_briefing.generated_at`. Compare `generated_at` to the last-seen marker:

```bash
_SEEN="$("<REPO>" seen)"
```

If `generated_at` is newer than `_SEEN` (or `_SEEN` is empty), there's a **new briefing since the user last visited this repo** — say so ("📰 New briefing for this repo, generated <date>"), then deliver it via Step 2 using `latest_briefing` (fetch the full briefing by id with the authenticated endpoint + `Accept: text/markdown`). After delivering, record what was shown:

```bash
"<REPO>" seen "<generated_at of the briefing just delivered>"
```

If `generated_at` equals `_SEEN`, there's nothing new — deliver the existing briefing as usual but skip the "new" banner.

**2. Offer / report the schedule.** Header generates scheduled briefings server-side on the goal, so they appear even when the user never opens a session. Fetch the goal to see the current schedule:

```bash
curl -sS -H "Authorization: Bearer $_HK" \
  https://joinheader.com/api/v2/goals/{default_goal_id}
```

Read `schedule_enabled`, `schedule_frequency_days`, `next_scheduled_generation`, `last_briefing_at`.

- **Not scheduled** (`schedule_enabled: false`) and `INTERACTIVE: yes` — offer once (track with a `~/.header/.schedule-offered` marker so it doesn't nag). Use `AskUserQuestion` on Claude Code, numbered plain text elsewhere:

  > Keep this repo's briefing fresh automatically? Header can regenerate it on a schedule.
  >
  > 1. Every 3 days
  > 2. Every 7 days (recommended)
  > 3. Every 14 days
  > 4. Every 30 days
  > 5. No thanks

  On a cadence choice, enable it on the goal:

  ```bash
  curl -sS -w "\n%{http_code}" -X PUT https://joinheader.com/api/v2/goals/{default_goal_id} \
    -H "Authorization: Bearer $_HK" -H "Content-Type: application/json" \
    -d '{"schedule_enabled": true, "schedule_frequency_days": 7}'
  ```

  Confirm ("✓ This repo's briefing will refresh every 7 days"). Always `touch "${HEADER_HOME:-$HOME/.header}/.schedule-offered"`.

- **Already scheduled** — don't re-offer. If useful, mention the cadence and `next_scheduled_generation` in one line. To change or stop it, the user can ask; PUT a new `schedule_frequency_days`, or `{"schedule_enabled": false}` to turn it off.

Best-effort throughout: if any call fails, fall back to the normal public flow — freshness and scheduling never block a briefing.

### Add a source

`/header-briefing add-source <url>` (or "add this source: <url>") feeds a URL into the user's topic. Requires a key. Topics draw from **source groups**, so the flow is preview → create → add to a group the goal already uses:

```bash
# 1. Preview (detect type, verify the URL)
curl -sS -X POST https://joinheader.com/api/v2/sources/preview \
  -H "Authorization: Bearer $HEADER_API_KEY" -H "Content-Type: application/json" \
  -d '{"url":"<url>"}'
# 2. Create the source (type from the preview: rss|youtube|reddit|newsletter|web)
curl -sS -X POST https://joinheader.com/api/v2/sources/ \
  -H "Authorization: Bearer $HEADER_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"<name>","type":"<type>","url":"<url>"}'   # → returns the source id
# 3. Add it to a source group the topic's goal already references
curl -sS -X POST https://joinheader.com/api/v2/source-groups/{group_id}/members \
  -H "Authorization: Bearer $HEADER_API_KEY" -H "Content-Type: application/json" \
  -d '{"member_id":"<source_id>"}'
```

Get the goal's `source_group_ids` from the topic and pick one the user owns. If none is editable, create a group (`POST /api/v2/source-groups/`), add the source as a member, then `PUT /api/v2/goals/{goal_id}` with `source_group_ids` including the new group. If the user has several topics, ask which. Confirm what was added; on a `*_FREE` tier error, run the trial/upgrade flow ("Tier limits and error handling").

### Check briefing status

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $HEADER_API_KEY" \
  https://joinheader.com/api/v2/briefings/{briefing_id}
```

Read the `status` and `summary` fields from the response. Status is `IN_PROGRESS` while generating, `COMPLETED` when ready, or `FAILED` on error.

**Markdown rendering:** the authenticated briefing endpoint honors content negotiation. Add `-H "Accept: text/markdown"` to receive a pre-rendered markdown document instead of JSON — no client-side parsing needed:

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Accept: text/markdown" \
  https://joinheader.com/api/v2/briefings/{briefing_id}
```

(Note: the public briefing endpoint `/api/v2/public/briefings/{id}` returns JSON only; markdown content negotiation is authenticated-path only.)

### Polling IN_PROGRESS briefings

The briefing-creation response (and any subsequent GET while the briefing is still in progress) includes a server-computed `estimated_duration_seconds` based on the number of sources assigned to the goal, plus `source_count`. Use the ETA for cadence — don't hardcode wait times.

**Cadence:** sleep `estimated_duration_seconds` before the first poll, then poll every 30s. Give up at twice the ETA and tell the user the briefing is taking longer than expected. If the field is missing or null, fall back to 300s (5 min).

**Blocking pattern** — when the user is waiting on the result:

```bash
# Trigger generation and capture the ETA from the create response
resp=$(curl -sS -H "Authorization: Bearer $HEADER_API_KEY" \
  -X POST https://joinheader.com/api/v2/goals/{goal_id}/briefings)
briefing_id=$(echo "$resp" | jq -r .id)
eta=$(echo "$resp" | jq -r '.estimated_duration_seconds // 300')

# Wait the estimated duration, then poll on a 30s interval until 2× the ETA
sleep "$eta"
deadline=$(( $(date +%s) + 2 * eta ))
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

**Non-blocking pattern** — when the user has other work to do:

1. Tell the user the briefing is generating, including the ETA from `estimated_duration_seconds` (e.g., "~5 min for 30 sources").
2. Record the `briefing_id` and return control.
3. On the next invocation, fetch by ID and present.

**Claude Code only:** non-blocking can be automated with `ScheduleWakeup` — set the delay to `estimated_duration_seconds` so the agent wakes when the briefing should be ready, without busy-waiting in the foreground.

### Generate a new briefing

For an existing goal (use `default_goal_id` from your topic):

```bash
curl -sS -w "\n%{http_code}" -X POST -H "Authorization: Bearer $HEADER_API_KEY" \
  https://joinheader.com/api/v2/goals/{goal_id}/briefings
```

### Update a goal

Refine the goal description or keywords based on what's most useful:

```bash
curl -sS -w "\n%{http_code}" -X PUT https://joinheader.com/api/v2/goals/{goal_id} \
  -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"description": "Updated focus areas...", "keywords": ["MCP", "agent memory"]}'
```

### Goal auto-tuning

Closes the loop: feed what the user applies / dismisses (the recommendation ledger) back into the topic's goal so future briefings sharpen. Requires an API key and a custom goal, **enterprise mode**, and is **opt-in** via `auto_tune`. `<LEDGER>` / `<HEADER_BIN>` are the helpers next to the preamble's echoed `HEADER_BIN`.

**Offer it once** when the ledger shows real signal — `<LEDGER> list --action applied --since-days 90` has 3+ entries — `auto_tune` is not already set, and no `~/.header/.autotune-offered` marker exists:

> You've applied several recommendations. Want Header to auto-tune this topic's focus from what you act on, so future briefings get sharper?

On yes → `<HEADER_BIN> set auto_tune true`. Always `touch "${HEADER_HOME:-$HOME/.header}/.autotune-offered"`.

**When `auto_tune` is `true`** (and a key + custom goal exist), after delivering a briefing, refine the goal from the ledger:
- Applied keys/titles (`<LEDGER> list --action applied --since-days 90`) = themes that resonate → add/emphasize their keywords.
- Dismissed keys (`<LEDGER> list --action dismissed --since-days 90`) = noise → de-emphasize those themes.
- Apply with one `PUT /api/v2/goals/{goal_id}` (see "Update a goal"), **merging** into the existing `keywords` / `description` — don't replace wholesale.

Best-effort: skip silently if there's no key, no custom goal, or no new signal. When you do tune, say so ("tuned your topic toward retrieval, away from X"). Tuning never blocks the briefing.

### Memory provisioning

Goals can be promoted to "memory-enabled" so future briefings retain context across runs (Forge-backed). Memory provisioning is asynchronous; poll the goal's `memory_state` until it reaches a terminal state.

Enable memory:

```bash
curl -sS -w "\n%{http_code}" -X PUT https://joinheader.com/api/v2/goals/{goal_id} \
  -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"memory_enabled": true}'
```

Poll `memory_state`:

```bash
curl -sS -H "Authorization: Bearer $HEADER_API_KEY" \
  https://joinheader.com/api/v2/goals/{goal_id} | jq -r .memory_state
```

| `memory_state` | Meaning | Action |
|---|---|---|
| `disabled` | Memory not enabled. | PUT with `memory_enabled: true` if desired. |
| `provisioning` | Forge is provisioning. | Poll every 30s; expect ~1–2 min. |
| `enabled` | Ready. Future briefings benefit from memory. | Terminal — proceed. |
| `error` | Provisioning failed. | Tell the user; retry the PUT or contact support. |

### Since-last digest

For "what's new since I last checked" (and the recommended shape for cron / `ScheduleWakeup`): pass the last-run timestamp to the dashboard so you only surface changes.

```bash
_HH="${HEADER_HOME:-$HOME/.header}"; _SINCE="$(cat "$_HH/.last-run" 2>/dev/null || echo)"
curl -sS -H "Authorization: Bearer $HEADER_API_KEY" \
  "https://joinheader.com/api/v2/topics/dashboard${_SINCE:+?since=$_SINCE}"
```

Surface only topics whose `next_action` is `briefing_ready` (see the table below); if nothing changed, say "nothing new since &lt;time&gt;" and stop. The skill writes `.last-run` after each briefing (see "Usage logging"), so the window manages itself.

**Session nudge (opt-in):** with `.last-run` tracking in place, a `SessionStart` hook or a scheduled `/header-briefing since-last` gives a quiet "a new briefing dropped on &lt;topic&gt;" at session start without a full fetch. Gate it behind a key so no-account users never see it.

### Scheduled / agent loop

For agents running on a cron or scheduled trigger (e.g., a daily check-in), use `GET /api/v2/topics/dashboard` with `?since=<iso8601>` to get only topics whose latest briefing changed after the timestamp. The response includes a server-computed `next_action` enum so the agent knows whether to surface a new briefing without re-deriving it client-side.

**Set `HEADER_NONINTERACTIVE=1`** in the environment of every scheduled / unattended run. The preamble reads it and suppresses the first-run welcome and the signup funnel — an onboarding prompt in an unattended run would block the job. (`CI=1` is treated the same way.)

```bash
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $HEADER_API_KEY" \
  "https://joinheader.com/api/v2/topics/dashboard?since=2026-05-01T00:00:00Z"
```

Per-topic `next_action` values:

| `next_action` | Meaning | Suggested behavior |
|---|---|---|
| `briefing_ready` | A new completed briefing is available. | Fetch `latest_briefing.id`, present to the user. |
| `briefing_failed` | The most recent generation failed. | Tell the user; suggest re-trigger via `POST /goals/{id}/briefings`. |
| `briefing_in_progress` | A briefing is still generating. | Apply the polling cadence above. |
| `nothing` | No change since `?since`. | Skip. |

Pass the timestamp from the previous run as `?since` so each tick only surfaces what's new.

For full API documentation, see [joinheader.com/docs](https://joinheader.com/docs).

## Response Reference

> **Source of truth:** the field names, types, endpoints, and error codes documented throughout this skill are a point-in-time snapshot. If the live API ever disagrees with what's written here — a field is missing, renamed, or a different type; an endpoint moved; a response doesn't match — **trust the API and fetch the latest contract from [joinheader.com/docs](https://joinheader.com/docs)** (e.g. `curl -sS https://joinheader.com/docs`, or the OpenAPI spec at `https://joinheader.com/api/v2/openapi.json`). Adapt to what the docs say; don't force the call to fit this snapshot.

### BriefingResponse

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Briefing UUID |
| `goal_id` | string | Parent goal UUID |
| `status` | string | `IN_PROGRESS`, `COMPLETED`, or `FAILED` |
| `summary` | string | Full markdown briefing text |
| `key_developments` | string | JSON-encoded array — parse from string into structured list |
| `source_articles` | array | Source articles used (title, url, metadata) |
| `estimated_duration_seconds` | int? | Server-computed ETA for generation, populated on the create response. Use it to drive polling cadence. May be null on completed/public briefings. |
| `source_count` | int? | Number of sources assigned to the goal at briefing time. May be null on completed/public briefings. |
| `stats` | object | Processing statistics (model, tokens, content window, etc.). |
| `is_public` | bool | Whether the briefing is publicly accessible |
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
