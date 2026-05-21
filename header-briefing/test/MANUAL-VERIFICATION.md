# Manual verification — Phase 0 + 1

Verification checklist for the enterprise foundation + onboarding work (state dir,
`header-config`, `VERSION`, the SKILL.md preamble, the signup funnel, `install.sh`).

- The **test suite** proves the scripts (`header-config`, preamble logic, `install.sh`,
  version parity).
- A **live `/header-briefing` run** proves the agent-interpreted onboarding (welcome,
  funnel timing, classic-mode notice, non-interactive suppression) — the suite cannot.

You are verifying *our scaffolding* (preamble, config, onboarding, install), not the
briefing content itself, which is Header's product. Live runs need network to
`joinheader.com`. Auto-update and telemetry are Phases 2 / 3 — not built, not verified here.

---

## Part 1 — Automated suite (30 seconds)

```bash
cd /home/workplace/Header-skill/header-briefing
./test/run.sh
```

- [ ] Output ends with `✓ all 4 suite(s) passed` (~52 assertions)

Each suite proves: `header-config` (get/set/list/defaults, key validation, sed-metachar
values, malformed files) · `preamble` (classic vs enterprise resolution,
`CI`/`HEADER_NONINTERACTIVE` → non-interactive, credentials read-not-sourced) ·
`version` (`VERSION` matches the `SKILL.md` frontmatter) · `install` (`install.sh` lands
a working skill, idempotent).

---

## Part 2 — Poke the scripts by hand (3 minutes, optional)

```bash
cd /home/workplace/Header-skill/header-briefing
export HEADER_HOME=/tmp/hdr-verify && rm -rf "$HEADER_HOME"

bin/header-config get language          # → English   (built-in default)
bin/header-config set language Turkish
bin/header-config get language          # → Turkish   (now persisted)
bin/header-config list                  # file contents + active values
cat "$HEADER_HOME/config"                # the flat key: value file
bin/header-config badsubcommand; echo "exit=$?"   # → usage error, exit=1
```

- [ ] `get language` returns `English`, then `Turkish` after `set`
- [ ] `list` shows the keys with `(set)` / `(default)` markers
- [ ] `badsubcommand` prints usage and `exit=1`

```bash
rm -rf /tmp/hdr-install
HOME=/tmp/hdr-install /home/workplace/Header-skill/install.sh
ls /tmp/hdr-install/.claude/skills/header-briefing        # SKILL.md  VERSION  bin  test
/tmp/hdr-install/.claude/skills/header-briefing/bin/header-config defaults
```

- [ ] `install.sh` prints `Installed -> ...`
- [ ] The installed folder has `SKILL.md`, `VERSION`, `bin/`, `test/`
- [ ] The installed `header-config defaults` runs

---

### Ledger & telemetry (scripts)

```bash
cd /home/workplace/Header-skill/header-briefing
export HEADER_HOME=/tmp/hdr-verify

bin/header-ledger record applied mcp-streaming --repo demo --title "MCP streaming"
bin/header-ledger status mcp-streaming --repo demo          # → applied
bin/header-ledger record dismissed mcp-streaming --repo demo
bin/header-ledger status mcp-streaming --repo demo          # → dismissed (latest wins)

bin/header-config set telemetry anonymous
bin/header-telemetry log skill_run --outcome success --recs-surfaced 2 --recs-applied 1
bin/header-telemetry sync --dry-run                          # the batch that WOULD be sent
```

- [ ] ledger `status` reflects the latest action (applied → dismissed)
- [ ] telemetry `sync --dry-run` shows the event but **no** `_repo` / `_branch`, and no `installation_id` (anonymous tier)

## Part 3 — Live test in Claude Code

### Setup

```bash
# a scratch project (your "empty codebase")
mkdir -p ~/header-skill-test && cd ~/header-skill-test
printf '{ "name": "scratch", "dependencies": { "react": "^18.0.0" } }\n' > package.json   # optional

# install the skill for real (the recommended path)
/home/workplace/Header-skill/install.sh

# sandbox the skill's state so it can be reset between scenarios
export HEADER_HOME=~/header-skill-test/.hdr-state
rm -rf "$HEADER_HOME"

claude        # launch a FRESH session in this dir (so it loads the updated skill)
```

Between scenarios, reset state by typing this in the Claude prompt (`!` runs a shell command):

```
!rm -rf ~/header-skill-test/.hdr-state
```

### Scenario A — first run, brand-new user

Run `/header-briefing`.

- [ ] A brief `👋 Header briefing skill` welcome line appears **first**
- [ ] A **language question** follows, with `English` marked as **recommended** (the default option)
- [ ] After picking a language (`English` to keep the default), the skill fetches and presents a **briefing**
- [ ] **After** the briefing, a 3-option question appears (New to Header / I have an account / Just public briefings) — never before the briefing *(decision D7)*

Pick **"Just public briefings."**

- [ ] `!ls -A ~/header-skill-test/.hdr-state/` → shows `.welcome-seen`, `.language-prompted`, `.signup-state`
- [ ] `!cat ~/header-skill-test/.hdr-state/.signup-state` → `public-only`
- [ ] Running `/header-briefing` again shows **no welcome, no language prompt, and no funnel** (each fires once)

*Optional:* pick `Spanish` or `Turkish` instead to confirm the next briefing's presentation gets translated; `!cat ~/header-skill-test/.hdr-state/config` should then contain `language: Spanish` (or whichever).

### Scenario B — "new to Header" path

Reset state, run `/header-briefing`, reach the funnel, pick **"New to Header."**

- [ ] It shows the `joinheader.com` signup link and offers to open it
- [ ] It walks through creating an API key with **read + write** access (write is required for custom topics)
- [ ] Declining to paste a key now sets `.signup-state` to `pending`
- [ ] A later `/header-briefing` re-offers the funnel once

### Scenario C — funnel skipped when a key exists

Reset state, then simulate a saved key (no relaunch needed — the preamble reads this file):

```
!mkdir -p ~/header-skill-test/.hdr-state && printf 'HEADER_API_KEY=hdr_sk_testfake\n' > ~/header-skill-test/.hdr-state/credentials
```

Run `/header-briefing`.

- [ ] The briefing is delivered
- [ ] **No signup funnel appears** (a key is present)

### Scenario D — classic mode (graceful degradation)

Hide the `bin/` folder so resolution fails:

```
!mv ~/.claude/skills/header-briefing/bin ~/.claude/skills/header-briefing/bin.off
```

Run `/header-briefing`.

- [ ] The briefing still works
- [ ] A one-line notice appears: *"classic mode - bin/header-config not found..."*
- [ ] No config, no onboarding

Restore it:

```
!mv ~/.claude/skills/header-briefing/bin.off ~/.claude/skills/header-briefing/bin
```

### Scenario E — scheduled / non-interactive (regression guard)

Needs a fresh session — environment variables are fixed per `claude` launch. Exit Claude, then:

```bash
rm -rf ~/header-skill-test/.hdr-state
HEADER_NONINTERACTIVE=1 claude
```

Run `/header-briefing`.

- [ ] The briefing is delivered
- [ ] **No welcome, no funnel** — onboarding fully suppressed (proves a cron / agent-loop run cannot be blocked by a prompt)

### Scenario F — update available (simulated endpoint)

The version endpoint isn't live yet, so simulate it with `HEADER_VERSION_JSON`. Quickest check is the script alone (no Claude needed):

```bash
HEADER_HOME=/tmp/h-upd HEADER_VERSION_JSON='{"latest":"99.0.0"}' \
  ~/.claude/skills/header-briefing/bin/header-update-check
# → UPDATE_AVAILABLE <your-version> 99.0.0
```

For the full agent flow, exit Claude and relaunch with the simulated response in the environment:

```bash
rm -rf ~/header-skill-test/.hdr-state
HEADER_VERSION_JSON='{"latest":"99.0.0","message":"Test update"}' claude
```

Run `/header-briefing`.

- [ ] Right after the preamble (before the briefing) the skill reports v99.0.0 is available and offers Yes / Always / Not now / Never
- [ ] **Not now** → no re-prompt this session; `!cat ~/header-skill-test/.hdr-state/update-snoozed` shows `99.0.0 1 <epoch>`
- [ ] Relaunch with `HEADER_VERSION_JSON='{"latest":"99.0.0","min_supported":"99.0.0"}'` → the skill reports an update is **required** (non-optional)
- [ ] With `update_check` set to `false` → no update prompt even with the simulated response

### Cleanup

```bash
rm -rf ~/.claude/skills/header-briefing ~/.codex/skills/header-briefing ~/header-skill-test
rm -rf /tmp/hdr-verify /tmp/hdr-install /tmp/h-upd
unset HEADER_HOME HEADER_VERSION_JSON
```

---

## What each step proves

| Step | Confirms |
|---|---|
| Part 1 | `header-config`, preamble logic, `VERSION` parity, `install.sh` (tasks T1–T4, T7) |
| Part 2 | The scripts behave by hand; `install.sh` produces a working install |
| Scenario A | Welcome + funnel exist; funnel fires **after** the briefing (D7); marker-gated once-only |
| Scenario B | Funnel "new user" branch; `pending` state + resume |
| Scenario C | `HAS_KEY` detection → funnel correctly skipped; credentials file read as data |
| Scenario D | Classic-mode fallback + visible notice (D3, codex finding #8) |
| Scenario E | Non-interactive guard — the mandatory regression test, live |
