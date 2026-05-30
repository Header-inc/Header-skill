# Changelog

Notable changes to the Header skill. Format roughly follows
[Keep a Changelog](https://keepachangelog.com); versions track the skill's `VERSION`.

## 0.15.0 — Cost-aware audit + a wider harness surface

The experiment engine was mature; the audit was thin — 8 phrase-greps, file sizes, and
a Bash-posture check over a fixed 8-file list. This release widens the funnel and makes
it generate the on-thesis hypotheses (model migration, supply-chain) instead of only
generic prompt-debt. Three things land, all in `bin/header-audit` + the SKILL.md flow.

### Cost-aware audit — `header-audit cost`

- **New `cost` subcommand** wraps `header-cost report --json` over your real Claude Code
  transcripts (`$HOME/.claude/projects/*.jsonl`, or `--input F`; `--since T` to scope)
  and reshapes it into audit rows: `SPEND-TOTAL`, `SPEND <model> <calls> <usd> <share>`,
  and `ROUTE-CANDIDATE` (the costliest model). All pricing stays in `header-cost` — the
  single source of truth for the table, cache-write split, and legacy-Opus handling.
- The audit now **opens with where the tokens actually go** and turns the top spend line
  into the headline **model-routing `[Experiment]`** — a candidate to *prove* with
  `header-experiment`, never a projected saving. No usage yet → a `NOTE`, handled
  gracefully. This is build-order step 1's "wire per-model spend into the audit so
  routing candidates surface," finally wired.

### Wider harness surface (past the 8 greps)

- **Hooks** — `HOOK <event> <command> <file>` from `settings.json`'s `hooks` key. Arbitrary
  shell on agent events: a bigger unguarded execution + supply-chain surface than the Bash
  allow/deny list, and previously unscanned.
- **Installed skills** — `SKILL <name> <path> <has-bin> <scope>` for `.claude/skills/`
  (repo + user). Skills carry instructions and optional bin scripts — a supply-chain
  surface (cf. `/cso`); Header is itself a skill, so this is dogfood-credible.
- **`@import` following + nested files** — the auditor now follows `@path` imports inline
  (`IMPORT` edges; imported files emitted as always-loaded `FILE` rows, so the per-turn
  token sum is no longer undercounted) and reports subdir `CLAUDE.md`/`AGENTS.md` apart as
  `NESTED` (on-demand, not every turn). Depth- and cycle-guarded; vendor/build trees pruned.
- **Model staleness** — `MODEL-STALE <value> <why>` when the pinned model names a superseded
  tier (Claude 3.x/2.x/instant, early Opus 4.0/4.1). Conservative — current ids aren't
  flagged; the briefing supplies the current target. Pure model-migration hypothesis.

### Two net-new finding types

- **Stale references** — `STALE-REF <path> <lineno> <ref> <why>`: a harness file names a
  path/script (backtick-quoted, path-shaped) or `@import`s a file that no longer exists.
  Deterministic and conservative (doc placeholders like `path/to/x` skipped); high-trust
  `[Apply with review]` material. SKILL.md also asks the agent to flag the semantic
  contradictions greps can't catch (tabs-vs-spaces, delegate-vs-never, dead flags).
- **Briefing-driven patterns** — `header-audit` now appends extra debt patterns from
  `${HEADER_HOME:-$HOME/.header}/patterns.tsv` (`HEADER_PATTERNS_FILE` to override): one
  `id<TAB>regex<TAB>why` line each, malformed lines skipped. The flow writes the briefing's
  named patterns there before scanning, so new hypotheses ship without a skill release.
  `header-audit patterns` lists them and notes the source.

Docs (Step 3/4, "What the audit scans", Cost analytics) updated throughout; `audit.test.sh`
grows from 24 to 49 assertions covering every new line type. No behavior change to `deps`,
`gate`, or the existing `harness` outputs.

## 0.14.1 — Hypothesis front-and-center in the synced payload

0.14.0 synced a `hypothesis` object that was *pointer metadata* — `ledger_key`, a
borrowed `title`, `source_url`, `disposition` — all recovered from the recommendation
ledger. When an experiment's ledger entry didn't exist yet at sync time (or a later
disposition like `snoozed` clobbered the earlier record's title to empty), the dashboard
showed an empty hypothesis even though the claim was right there in the spec's
`description`. The human-readable hypothesis was never actually sent as such.

- **New first-class `hypothesis:` spec field** — the full claim being tested, in words.
  `build_payload` emits it as `hypothesis.statement`, the dashboard headline. It comes
  from the spec (falling back to `description`) and is **never reconstructed from the
  ledger**, so a missing or snoozed ledger record can no longer empty it.
- **`--hypothesis` flag** on `new` and `define`; `write_spec` and both scaffolders write
  the field (defaulting to the description). `validate` accepts it (no allowlist change
  needed — it's a top-block scalar).
- `ledger_key`/`title`/`source_url`/`disposition` stay in the object as **provenance**,
  blank unless the experiment traces to an audit finding. `hypothesis` is now non-null
  whenever a statement exists (i.e. almost always), not only when tied to a finding.
- Docs (SKILL.md, `docs/experiments-sync-api.md`) and the `push` payload contract updated;
  new `push.test.sh` coverage asserts the statement beats `description`, survives a
  snoozed ledger record, and keeps `ledger_key` as provenance.

## 0.14.0 — Experiment cloud sync — automatic when a key is present (client side)

Experiments now sync to the user's Header account so they show up in the web UI:
*which experiment, testing which hypothesis, from which goal/topic/briefing, on which
repo and machine, and how it came out* — with a last-known **status** (`defined → run
→ analyzed → merged`) the UI can track. Nothing runs server-side — the runner stays
local; this is the user's own dashboard record, distinct from the (still-future,
still-anonymized) cross-customer aggregate submit.

### Automatic sync, not a prompt

- **Every lifecycle change auto-syncs when a key is present** — `new`, `define`,
  `validate` (the "I edited the spec" hook), `run`, `analyze`, `merge` each fire a
  best-effort sync and print a faint `⤴ dashboard: …` line. No per-edit prompt: having
  an API key configured *is* the opt-in.
- **No key → a once-per-experiment recommendation** to connect an account. Never blocks.
- **Opt-out:** new config key `experiment_sync` (`auto` default · `off`). It is
  **personal-only** — `TEAM_SENSITIVE`, so a committed team config can't enable egress
  for teammates. `HEADER_EXPERIMENT_NOSYNC=1` disables it for one invocation / CI.
- A local `~/.header/experiments/<id>/.last-sync` marker (`<iso> <http_code>`) records
  the last sync result for offline inspection.

### `header-experiment push` (manual sync / preview, same payload)

- **Payload** = experiment (id/kind/description/arms/**status**) · hypothesis (the audit
  finding, recovered from the ledger via `ledger_key`) · audit_basis (topic + goal +
  briefing) · repo (normalized git remote + commit) · machine (install id + host/os/arch)
  · result (verdict + CIs, verbatim). Idempotent **upsert** on
  `client_key = <installation_id>:<experiment_id>`.
- **Privacy contract.** Metadata only. **Task prompt bodies, override file contents,
  and agent logs never leave the machine.** Prompts are identified by a sha256 + byte
  count. Each task carries a descriptive **title** resolved authored → derived → id:
  an authored `title:` in the spec is sent verbatim (zero-leak); else a one-line summary
  is *derived* from the prompt's first heading (descriptive, low-leak); else the task id.
- **Flags.** `--dry-run` prints the exact JSON (no key needed) for review; `--all` syncs
  every local experiment; `--topic` / `--goal` / `--briefing` supply session lineage the
  ledger lacks (they win over the ledger).

### Backend status

**The receiving endpoint is not live yet.** `POST /api/v2/experiments` currently returns
`405` server-side; the client makes the call anyway so the contract is exercised
end-to-end against the real host. The backend implements the handler against the shape
documented in SKILL.md ("Sync an experiment (`POST /api/v2/experiments`)"). Until then,
sync reports the `405`/`404` clearly, saves locally, and retries on the next edit.

### Supporting changes

- **`header-ledger get <key>`** — print the latest full JSON record for a key (title,
  briefing_id, topic_id, source_url) so sync can recover a finding's provenance in one
  call. Exit 0 on a valid-but-empty lookup (exit-code hygiene).
- `beta_banner` states the egress honestly (local runner; metadata auto-sync when keyed).
- Tests: new `test/push.test.sh` (45 assertions — payload shape, lineage recovery, the
  body-never-leaves contract, kind inference, title resolution, the `experiment_sync`
  closed-domain + team-sensitivity, the no-key recommend-once, the `off`/`NOSYNC`
  switches, and the status lifecycle) + `get` coverage in `test/ledger.test.sh`.

## 0.13.1 — Safety guard for misplaced lifecycle keys + post-0.13.0 doc sync

**Landmine fix.** `setup:` / `teardown:` / `setup_scope:` are read by
`spec_get_scalar`, which only sees the spec's top block — so a key placed *below*
a `[section]` was silently ignored: no infra provisioned, and the run quietly hit
the repo's real DB (false isolation, worse than not having the feature). `validate`
now hard-errors on a lifecycle key found below the first `[section]`, naming the
fix. Regression-tested.

**Doc sync to 0.13.0 reality** (the prose had drifted behind the code):
- `ROADMAP.md` — moved ephemeral-infra / cost-axis / guardrail-value out of "not
  yet built" (they shipped in 0.12.x–0.13.0) into the shipped list; the remaining
  "next" item is now tool-managed provisioning.
- `SKILL.md` — fixed the experiments intro (`merge` + the `setup`/`teardown`
  lifecycle are in scope) and a stale line calling `merge` "a future subcommand."
- `README.md` — corrected the verdict list (`underpowered` → `data degenerate`
  (N=1) + `WIDE CI / LIMITED POWER` at N=2–4) and added a one-line lifecycle note.
- `llms.txt` — refreshed the `header-experiment` entry (pre-spend honesty,
  both-axis discrimination, guardrail-value, ephemeral-infra lifecycle).
- `docs/experiments-design.md` — un-stale'd §12's "(NOT yet built)" title and
  added §14 cataloguing everything shipped beyond the original design.

## 0.13.0 — Experiment engine: ephemeral-infra lifecycle, cost-axis discrimination, guardrail-value mode

Three experiment-engine milestones from the 0.12.5 field test, turning "the
worktree can't run infra-dependent mandates" from a dead-end into a workflow.

### 1) Ephemeral-infra lifecycle (`setup:` / `teardown:` / `setup_scope:`)

`worktree_include` symlinks *files*; stateful (DB-touching) experiments need an
*isolated service*. New top-level spec keys:
- **`setup:`** — a shell command run before the matrix. Its stdout `KEY=VALUE`
  lines are captured to `<exp_dir>/.run-env` and exported into **every run's
  adapter and verifier** — so the agent and the oracle both hit a throwaway
  DB/branch (e.g. an injected `DATABASE_URL`), never prod/beta. Each line is
  passed as a single arg to `export`, so a connection string's `&?:` aren't
  re-parsed by the shell.
- **`teardown:`** — destroys the infra. **Guaranteed to run** via an
  `EXIT`/`INT`/`TERM` trap (reads globals + the on-disk `.run-env`, so it fires
  even after `cmd_run` returns or on Ctrl-C) and is idempotent.
- **`setup_scope:`** — `experiment` (default; provision once) or `run`
  (provision + tear down per `(task, arm, rep)` for write-heavy tasks where one
  run's writes would contaminate the next). `validate` rejects other values.

Scaffolded specs get commented placeholders; SKILL.md documents the contract,
the `run`-scope churn/cleanup tradeoff, and the `.env`-shadows-injected-env
footgun.

### 2) Cost-axis non-discrimination caveat

The discrimination warning guarded the *success* axis; `report` now guards the
*cost* axis. For a mandate-deletion A/B whose cost comes back **not favorable**
(arm A not measurably costlier than arm B), it prints a caveat: the mandate may
be genuinely cheap, OR the adapter never *performed* the mandated work (a
one-shot headless run won't boot a server / drive a browser) — a false "the
mandate is free." Detected by diffing arm overrides vs. the repo + mandate
keywords; gated on `favorable=false` so genuine wins stay quiet.

### 3) Guardrail-value mode

`new --kind prompt-debt-deletion` on an emphatic mandate now recommends treating
"is this guardrail earning its cost?" as a **guardrail-value question**, not an
A/B: cost is cheap to measure (one execution), benefit is tail-risk insurance
unmeasurable at small N. SKILL.md names the mode and makes "measure cost
directly, reason about benefit qualitatively" the default.

## 0.12.5 — Reframe the discrimination gotcha: stack bring-up in a worktree is supported, not a dead-end

Field-test feedback (a real run pressure-testing a Playwright visual-verify
mandate): the 0.12.3 discrimination gotcha was too defeatist — it treated "this
mandate needs infra the worktree can't trivially provide" as the signal to give
up and `[Apply with review]`. But the run's own investigation showed the stack
*could* come up (deps present, DB reachable). Reframed: bringing the stack up
inside the worktree is a **supported path** (`worktree_include` for files;
per-experiment ephemeral DBs/branches are a ROADMAP milestone), with a real
wall-clock + provisioning cost — weigh it, don't reflexively bail just because
infra is involved.

Also added the **cost-axis twin** of the discrimination trap: bringing the stack
up is necessary but not sufficient — if the run adapter (often a one-shot
headless invocation) doesn't actually *perform* the mandated work, arm A's cost
collapses onto arm B's and you get a false "the mandate is free."

ROADMAP gains three experiment-engine milestones the field test surfaced:
**per-experiment ephemeral infra** (`setup:`/`teardown:` lifecycle, isolated
DB/branch per run, guaranteed cleanup, granularity model), **cost-axis
non-discrimination detection**, and a **guardrail-value mode** (measure cost
directly; benefit is tail-risk, unmeasurable at small N).

## 0.12.4 — Exit-code hygiene: bin tools must not leak a non-zero status on success

A real run hit `header-audit harness` emitting a complete audit (SECURITY +
FILE rows) but exiting **1** — which the agent harness surfaced as
`Error: Exit code 1` and used to cancel the parallel tool calls that followed.
Audited all eight `bin/` tools for the same class of bug.

### `header-audit` exited 1 on a clean audit (the real bug)

The `harness` branch ends in a globbed `for f in …/.claude/commands/*.md
…/.claude/agents/*.md` loop whose body is `[ -f "$f" ] && scan_file "$f"`. In
POSIX sh with no nullglob, a directory that doesn't exist leaves the glob
literal, so the final `[ -f ]` test is false → the loop (and the whole script,
which had no trailing `exit`) returns 1. `scan_file`'s trailing `grep`-pipeline
leaks the same way when a file has no cargo-cult HITS. Fixed with a success-path
`exit 0` at end of script — the auditor is a best-effort, read-only row emitter,
and genuine usage errors still `exit 1` inline above it.

### `--help` exited 1 on 7 of 8 tools

Every tool except `header-update-check` routed `--help` to the same code path as
a no-arg/unknown usage error (`exit 1`). Explicit `--help` is a success action;
it now exits **0** (printing to stdout) across all tools, while no-arg and
unknown subcommands still exit **1** (to stderr). For `header-cost` /
`header-experiment` the shared `usage()` now takes `usage 0` for the help case;
the four dispatcher tools (`config`, `ledger`, `repo`, `telemetry`) and
`header-audit` gained an explicit `-h|--help` branch.

### Not leaks (verified, left as-is)

`header-config get <bad-key>` → 1 (genuine invalid-key error), `header-cost cost
<unknown-model>` → 2 (genuine unknown-model error), and `header-cost report` /
`savings` reading usage JSONL from `/dev/stdin` (by design — pipe data in or
redirect `</dev/null`). All real data/action subcommands across every tool
already exit 0 on success.

New `test/binexit.test.sh` locks in: `--help` = 0 everywhere, unknown subcommand
= 1 on dispatchers, and `header-audit harness`/`deps`/`patterns` = 0 on a clean
repo with output intact.

## 0.12.3 — Pre-spend honesty: catch a doomed experiment before the tokens burn, not at `analyze`

Five fixes from a real 0.12.2 run — a CLAUDE.md trim that got scaffolded as an
A/B, run to completion (12 Haiku sessions), and only revealed at `analyze` time
that it could never have measured anything. Every fix moves a warning that
already existed *after* the spend to *before* it, and closes the gap that let a
hand-rolled spec skip the guardrails entirely.

### 1) `validate` warns on the degenerate 1-task CI (before any spend)

A 1-task A/B is mathematically degenerate — the paired-by-task bootstrap
resamples a single task, so the cost & success CI collapse to a point and
`analyze` returns `data degenerate`, never `B wins`. That verdict already
existed, but only *after* the run. `validate` (and `run`'s pre-flight) now say
so up front: add ≥2 tasks for a real CI, or read the run as a pass/fail sanity
check. (A/A noise-floor runs are still fine at 1 task × ≥2 replicates — the
replicate-level fallback covers them.)

### 2) `--yes` skips the prompt, not the disclosure

`--yes` previously skipped the *entire* cost gate — so an authorized
non-interactive run printed nothing, and the "don't run a \$60 experiment to
prove a \$0.10 effect" framing never made it onto the record. Now the disclosure
always prints when there's no `--adapter`; `--yes` only suppresses the
interactive confirmation, and prints `(--yes given — spend authorized…)` so the
rationale is logged before the tokens burn.

### 3) The measured noise floor is surfaced at the A/B gate

`run --aa` measures the harness's run-to-run noise floor, but nothing fed that
back into the A/B decision — you'd discover your effect was sub-noise only at
`analyze`. Now, if a `result-aa.json` exists, the A/B gate prints the measured
cost-CI half-width: *"an effect smaller than ~\$X/task won't separate from
noise."* No A/A on record → it nudges you to run `--aa` first. (Groundwork for
the ROADMAP's σ-based power analysis; the comparison is surfaced, not yet
auto-enforced.)

### 4) Prompt-debt discrimination warning — incl. hand-rolled specs

The biggest gap. A trim experiment only measures something if the verify task
*exercises the trimmed instruction*; otherwise both arms behave identically and
"3/3 both arms" proves the task was easy, not that the cut was safe — and a
regression-style verify (`npm test`) is blind to adherence drift. The 0.12.2
guardrails lived only in `new --kind prompt-debt-deletion`, so the real run's
**hand-rolled** spec bypassed them all. `validate`/`run` now detect prompt-prefix
deletions generically — by diffing each arm's `overrides_dir` `CLAUDE.md`/
`AGENTS.md` against the repo's copy — and warn that the task must exercise the
cut. When the deleted text carries an emphatic mandate (`MUST`/`NEVER`/`ALWAYS`,
case-sensitive so sentence-case cargo-cult like "Always think step by step"
doesn't cry wolf), it escalates: a regression verify can't see adherence drift.
The scaffold path (the magnitude estimator) prints the same warning.

### 5) Honesty rule — announce a disposition change mid-flight

SKILL.md now codifies the root cause of the whole episode: if you flag a finding
`[Experiment]` and then act under `[Apply with review]` (or vice versa), say so
and why *before* acting. Silently applying under a different disposition than the
one you announced reads as sleight of hand, even when the new call is right.

## 0.12.2 — Soft power gate, replicate-level A/A, worktree isolation fix, multi-task scaffold, audit nudges

Five fixes from a second real-world experiment run that exposed the next
layer of edge cases. The 0.12.1 "underpowered = refuse" cliff was too
strict; the 0.11.x worktree isolation was actively misleading; `new` was
single-task-only; and prompt-debt deletions on CLAUDE.md often measure
nothing because hooks already enforce the behavior.

### 1) Soft power gate (replaces the 0.12.1 `<5 → refuse` hard cliff)

`<5 paired tasks` is no longer a refusal. Three power tiers:
- **N=1 paired-by-task** — verdict `data degenerate` (genuinely refuse — the
  bootstrap CI is mathematically a single point).
- **N=2-4** — analyze normally but flag `WIDE CI / LIMITED POWER at N=n` in
  the verdict + a banner in the report. CIs are wide but real; suppressing
  them threw away honest information.
- **N≥5** — standard verdict, no caveat.

User-driven via the AskUserQuestion dialog: "Soften gate + replicate-level
A/A fallback." Picks the right answer for both A/A bias-detection (small N
fine if K is large) and A/B effect-detection (N gets tiered, not refused).

### 2) Replicate-level A/A fallback (the right analysis for low-N harness checks)

A/A asks *"is the harness biased?"* — really *"do A and A_2's cost
distributions differ systematically?"* With N=1 task and K≥2 replicates per
arm, that's a 2-sample question on K values per arm, not a paired-by-task
question on 1 task. `analyze --aa` now switches to **unpaired bootstrap on
within-task replicates** when tasks_paired==1. So `1 task × 10 reps` gives
real bias-detection power (vs. the old false-positive `A/A BIASED` from a
degenerate paired-by-task CI). `result.json` carries
`analysis_method: "replicate-level"`; report banner names it. A/A with N=1
and <2 reps per arm still hits `A/A data degenerate` (can't do either
analysis with that little data).

### 3) Worktree-include — fix the silent-success class of bugs

`git worktree add --detach` brings only TRACKED files. No `venv/`,
`node_modules/`, `.env`, or editable-installed packages. The 0.11.x runner
silently let `pytest` execute against the *parent repo's* code (via the
editable install resolving to the original path) — both arms passed, but
arm B's actual edits were never tested. The worst kind of false-positive.

Two-part fix:
- New optional top-level spec field **`worktree_include: venv, .env, ...`**
  — comma-separated repo-relative paths that get symlinked into each run's
  worktree before the agent invokes. Skips paths that don't exist
  (warning), skips paths that already exist as tracked files in the worktree
  (warning).
- When `worktree_include` is unset, `run` prints a one-line reminder before
  the cost gate ("worktrees contain only TRACKED files; if your verify needs
  venv/, .env, set worktree_include:"). When set, the reminder is
  suppressed — configured users aren't lectured.
- Scaffolded specs (`new`, `define`) get a commented `# worktree_include:`
  placeholder so the field is discoverable when editing the spec.

### 4) `--task` is now repeatable

`new` was single-task only — every scaffolded experiment was N=1 by
construction, which collided with the soft power gate (always
`data degenerate` for A/B). Now `--task` is repeatable:

```bash
header-experiment new my-exp --arm A: --arm B: \
  --task "Refactor X" --task "Refactor Y" --task "Refactor Z" \
  --verify "pytest -x -q"
```

Each `--task` becomes a `[task:tN]` section (numbered t1, t2, t3 in flag
order). Inline prompts get written to `<exp_dir>/tasks/tN.md`; file paths
are stored as repo-relative. Interactive mode still asks for one task; for
multi-task pass them all via flags.

### 5) Two scaffold-time nudges

**Cache-read pricing nuance** — in the magnitude estimate for
`--kind prompt-debt-deletion`, surface that prefix tokens live in the prompt
cache and price at ~10% of regular input rates on cache reads. Both proven
savings AND experiment cost scale down by the same factor, so the
cost-vs-magnitude ratio is preserved — but the headline dollar / headroom
impact is smaller than the raw token count suggests.

**Pre-existing enforcement nudge** — for prompt-debt deletions targeting
CLAUDE.md / AGENTS.md (the actual case from the 2026-05-27 run), `new`
prints: *"Before scaffolding: check whether other mechanisms already enforce
what those lines say — pre-commit hooks (.git/hooks/), CI rules
(.github/workflows/), Claude Code hooks (.claude/settings.json hooks: section).
If a hook is the real source of truth, the CLAUDE.md text is redundant and
the experiment will measure nothing because both arms behave identically."*
Other-file deletions don't trigger it (kept narrow to the actual failure
mode).

### Tests

+30 assertions covering soft gate at N=2-4 (verdict + LIMITED POWER caveat,
CI not suppressed), replicate-level A/A (clean + biased verdicts, "1 task
× K reps" framing, <2-reps degenerate fallback), worktree_include
(symlinks present in worktree, missing paths warned not fatal, default
warning suppressed when configured), multi-task scaffold (t1/t2/t3
sections + files), cache-read pricing nuance, CLAUDE.md enforcement nudge
(present on CLAUDE.md, absent on other files). 176 in experiment suite,
430 total; all 11 suites green.

### Doc changes

- SKILL.md "Experiments" section: power tiering explained,
  `worktree_include` mentioned, `--task` repeatability called out.
- `docs/experiments-design.md` §6.3: implementation status updated with the
  three power tiers + replicate-level fallback. §0 status header bumped to
  v0.12.2.

## 0.12.1 — Four honesty fixes from a real-world 0.11.x run

Real feedback from running the experiment engine on a `synthesize-engine`
audit-driven A/B (the "slim CLAUDE.md" experiment from the 2026-05-27
session). Four bugs that made the report dishonest in edge cases:

1. **`analyze` averaged $0 timeout rows into the cost mean.** When a
   replicate hit the agent-invocation `timeout_s` wall, claude was killed
   before emitting the final JSON; `cost_usd` parsed as 0 with
   `agent_exit=124`. Today `analyze` averaged that into the arm, dragging
   the mean down and producing a misleading "B is $1.43 more expensive"
   verdict. Now: rows with `agent_exit ≠ 0` are excluded; `result.json`
   carries `excluded_runs: N`; `report` prints a banner ("Excluded 1 of 6
   runs (agent_exit ≠ 0 — timeout or error). Cost/success means use clean
   runs only.").

2. **Degenerate CI printed as if it were precise.** A 1-paired-task analysis
   makes the bootstrap mathematically degenerate — all resamples pick the
   same point, so the CI collapses to `[1.43, 1.43]`. The verdict already
   said "underpowered," but the CI line still printed those numbers as
   though they meant something. Now: when `verdict ~ /^underpowered/`, the
   report shows `(insufficient data)` for both the cost and success CIs,
   and the conservative-savings line is suppressed ("not computed —
   insufficient data"). Raw numbers stay in `result.json` for the record;
   only the human-facing report suppresses them.

3. **Default `timeout_s: 600` was too tight for realistic tasks.** Ten
   minutes is fine for a 5-turn refactor; a 60-80-turn coding task hits
   the wall. Default in scaffolded specs (`new` + `define`) bumped to
   1200. `run`'s runtime fallback also raised to 1200. The cost gate
   already names "shorter tasks" as a lever; the *default* shouldn't
   punish people running realistic-sized ones.

4. **`new`'s auto-detected verify is a regression check, not a
   task-completion check.** `npm test` / `pytest` / `cargo test` answer
   "does the suite still pass?" — they don't answer "did the change
   actually happen?" When `--verify` is omitted and we auto-detect from
   the manifest, `new` now prints a Note explaining the distinction with
   an example: `verify: npm test && curl ... | jq '.new_field != null'`.
   Nudge fires only on auto-detect; user-supplied verifiers stay quiet.

Tests: +13 assertions (excluded-runs banner + math; underpowered CI
suppression + result.json preservation; default timeout in both define
and new templates; verify nudge presence on auto-detect, absence on
explicit). 146 in experiment suite, 400 total; all 11 suites green.

## 0.12.0 — Cost-vs-magnitude gating: don't run a $60 experiment to prove a $0.10 effect

Promoted from §13 open-question to a real design constraint after the
2026-05-27 audit, when a `slim CLAUDE.md` experiment scaffolded by `new --kind
prompt-debt-deletion` would have cost ≈$60 of API-equivalent spend (or the
equivalent in usage-limit headroom on a Max subscription) to prove ≈$0.10/session
in savings. The runner did its job — the JSON exposed the real numbers — but
the audit had no business labelling that finding `[Experiment]` in the first
place.

**The audit is now a two-stage filter, not just a generator.** Stage 1 still
generates hypotheses from prompt-debt patterns, briefing items, and supply-chain
posture. Stage 2 (new) sorts each into three dispositions by the
cost-vs-magnitude ratio:

- **`[Apply now]`** — strictly deterministic, low-risk: security patches, gate
  snippets, doc typos. Unchanged.
- **`[Apply with review]`** _(new)_ — small-magnitude AND diff-faithful: cargo-cult
  deletions, role-puffery removal, doc cleanups. The user is the verifier; show
  the diff. Optionally one sanity replicate (`run --k 1`); skip the full
  bootstrap A/B.
- **`[Experiment]`** — diff-opaque OR high-magnitude, AND the experiment can be
  run cheaply enough that the ratio is defensible.

**Both levers are first-class.** The dividing line isn't a magnitude threshold —
it's a *ratio*. A tiny-magnitude question is still fair game for `[Experiment]`
if you spend on the cost-lever side: Haiku adapter for prefix-only experiments
(the model isn't what's tested; the prefix effect transfers), `--k 1`
sanity-only, narrower verify, shorter task prompts.

### Code changes

- **`header-experiment new --kind prompt-debt-deletion`** prints an up-front
  **magnitude estimate** (removed bytes / total bytes, ~est tokens). When the
  change is <5% of the file, surfaces **both** paths: `[Apply with review]` AND
  cheaper-experiment levers. Doesn't block — just informs.

- **`header-experiment new --kind clause-add`** _(new)_ — INSERTION experiments.
  `--file F --after-line N (--text "..." | --text-file F)` inserts content after
  line N in F (0 = top of file) into arm B's overrides. Unblocks behavior-change
  experiments the deck has wanted forever: mandatory-skill rules, delegation
  toggles, fast-mode instructions, framework-migration patches — all things
  `prompt-debt-deletion` couldn't express because they ADD a clause rather than
  remove one.

- **`header-experiment run`'s cost gate** now speaks BOTH billing modes
  (mirrors `header-cost`'s existing framing): API/Console pay-per-token vs.
  Claude subscription usage-limit headroom. Quotes the load-bearing rule
  verbatim. Lists the cheap-experiment levers — Haiku adapter, `--k 1`,
  narrow verify, shorter tasks.

### Doc changes

- **`SKILL.md`** — `[Apply with review]` is the new audit disposition. The
  dividing line between it and `[Experiment]` is explicitly the *ratio*, with
  both levers (magnitude + experiment-cost) named. Quotable principle baked in.
- **`docs/experiments-design.md`** — new **§6.8 Magnitude vs. experiment cost**:
  the audit is a two-stage filter, both ratio levers are first-class. §13 entry
  for "Cost of experimenting" marked promoted to design constraint.

### Tests

+33 assertions covering the three-disposition split: cost gate dual-mode
framing (mentions both billing bases, quotes the load-bearing rule, lists
cheap-experiment levers); magnitude estimate at scaffold time (prints %,
fires <5% pointer below 5%, suppresses it ≥5%); `clause-add` materialises
arm B's file at the right insertion point (`--after-line 0` = top,
`--after-line N` = after line N), accepts `--text` and `--text-file`, rejects
bad inputs. 133 in experiment, 387 total; all 11 suites green.

## 0.11.2 — `header-experiment run`: clean refusal in agent subshells (no `/dev/tty` leak)

Bug fix. `header-experiment run` without `--yes` (and without `--adapter`)
previously tried to read the cost-gate confirmation from `/dev/tty`. In an
agent subshell `/dev/tty` exists as a file but `open()` returns ENXIO (no
controlling terminal), and bash's redirect-failure error escapes `read`'s
`2>/dev/null`. The result was an ugly:

```
/.../header-experiment: line 818: /dev/tty: No such device or address
header-experiment: aborted
```

`cmd_run` now checks `[ -t 0 ]` (same pattern `prompt_user` already used)
and refuses with a helpful pointer:

```
header-experiment: no TTY for confirmation — re-run with --yes to authorize
the spend non-interactively (or set --adapter to use a stub for testing)
```

So agents driving the runner in headless contexts get a clean signal of
what's needed instead of a misleading "No such device" error.

Tests: +4 regression assertions (no `No such device` leak; refusal message
mentions `--yes`). All 11 suites green (104 in experiment, 358 total).

## 0.11.1 — `header-experiment`: audit-aware `new`, one-step `merge`

Closes the audit → experiment → applied-change loop in code, not just in
SKILL.md prose. The `[Experiment]` finding the audit surfaces becomes a
runnable spec with one command, and the winning arm gets applied with one more.

**`header-experiment new <id>`** — the recommended scaffolder. Three flavors,
all producing a complete, runnable spec in one call (no editor needed for the
common case):

- `--kind prompt-debt-deletion --file F --lines L1,L2,...` — the §8 wedge.
  Arm A = current state; arm B = F with those lines stripped (the wizard runs
  the `sed` and writes the override into `arms/B/F`). Wire it directly to a
  `HIT` from `header-audit harness` — the audit already prints the file and
  line numbers.
- `--kind model-swap --from M --to N` — two arms differing only in model.
- Generic `--arm A:model[:overrides_dir] --task PATH-OR-INLINE --verify CMD` —
  caller specifies arms directly; useful for dep upgrades / behavioural
  rewrites where arm B's overrides need to be hand-prepared.

Path resolution flipped: `--task` and the spec's `prompt:` paths now resolve
**relative to the repo** first (where users naturally put `tasks/*.md`),
falling back to the experiment dir for files the wizard generated. Was
experiment-dir-only before — that wasn't useful.

Inline prompts: `--task "Refactor the auth module..."` writes the text to
`<exp_dir>/tasks/t1.md` automatically. No more "create a .md file first."

Auto-detected verify: omitting `--verify` picks `npm test` / `cargo test` /
`pytest -q` / `go test ./...` / `bundle exec rake test` based on which
manifest the repo has. Interactive sessions show it as the default.

`--ledger-key` carries the audit-finding key into the spec's top block — so
`merge` can suggest the right `Header-Audit-Finding:` commit trailer when the
experiment came from an audit finding.

**`header-experiment merge <id>`** — applies arm B's override files into the
repo after a B-wins verdict. Refuses other verdicts unless `--force`. Shows a
unified diff per file and asks for confirmation (`--yes` skips). For
model-swap experiments (no override files) it prints a "update your default
model to <B's model>" note + the ledger hint, but doesn't pretend to mutate
your runtime model selection (that lives outside the skill). Does NOT
auto-commit; prints a suggested `git commit` invocation with the
`Header-Audit-Finding: <ledger-key>` trailer (the same trailer pattern 0.10.1
introduced for audit-driven applies).

**SKILL.md**: the audit → experiment handoff is now concrete instructions,
not just a pointer. When the user picks an `[Experiment]` finding, the agent
constructs the appropriate `header-experiment new --kind ...` invocation from
the finding's payload (file/lines for prompt-debt; from/to model for swap);
the wizard fills in the rest from project manifests.

**Caveats / honest scope notes** (carried into the design doc):
- The "<5 paired tasks → verdict = underpowered" cutoff is a *heuristic*, not
  a power analysis. Real σ-based power sizing comes once A/A surfaces σ.
- Cost is read from claude's `total_cost_usd`/`cost_usd`. If those fields are
  absent in a future Claude Code release, cost falls to 0 silently — should
  add a `tokens × header-cost` fallback (latent bug, not current).
- Tier-1 oracle only (exit-code verifier). LLM judges deferred.

Tests: +39 assertions for `new` (all three modes, ledger_key placement,
arm B materialization, bad inputs) and `merge` (B-wins, no-win refusal,
--force, A/A refusal, model-swap path, trailer suggestion). Total 100 in the
experiment suite; all 11 suites green (354 assertions).

## 0.11.0 — `header-experiment` MVP (beta): local A/B + A/A for harness changes

The first runnable slice of the optimization-by-experimentation loop. **Beta —
local-only, interface may still shift.** New helper `bin/header-experiment` with
five subcommands:

- `define <id>` — scaffold a spec (flat `key: value` lines + repeated `[arm:X]` /
  `[task:Y]` sections) under `~/.header/experiments/<id>/`.
- `validate <id>` — lint the spec.
- `run <id> [--aa] [--k N] [--yes] [--adapter CMD]` — execute the matrix in
  isolated `git worktree`s at a pinned commit. Each `(task × arm × replicate)`
  invokes the agent (default: `claude --print --output-format json`), parses
  usage from the JSON, then runs the user-specified `verify` command as the
  Tier-1 oracle (exit 0 = success). `--aa` is the noise-floor / harness validator
  (§3 of the experiments design); a tests-only stub adapter is wired via
  `$HEADER_EXPERIMENT_ADAPTER` so the test suite never spends real tokens.
- `analyze <id> [--aa]` — pair by task, bootstrap CI (default 2000 iters,
  seedable) on per-task differences for cost (USD) and success rate.
- `report <id> [--aa]` — pretty scorecard with the §6.5 decision rule (merge B
  iff cost CI upper bound < 0 AND success lower bound ≥ −δ) plus a
  **conservative savings rate** = `max(0, -upper_CI(diff_cost))` so we never
  bill the optimistic tail.

**Cost gate.** `run` refuses to launch silently — it states the invocation count
(`tasks × arms × replicates`) and prompts for confirmation. `--yes` skips it.

**Verdicts** are explicit about the failure modes that look like wins:
- `underpowered` — `<5` paired tasks; the bootstrap is too tight to call.
- `no proven win` — cost favorable but success regressed beyond δ, or cost CI
  contains 0.
- `A/A BIASED` — cost CI for an A/A excludes 0; the harness is contaminated
  (ordering / cache warmup / temporal drift), fix it before trusting the A/B.

**Explicit cuts (not yet built; tracked in [ROADMAP](ROADMAP.md)):**
- `header-experiment mine` — git-history task mining (§11 of design).
- `header-experiment merge` — auto-apply the winning arm's diff to the harness.
- LLM judges, multi-comparison FDR / sequential analysis, cross-customer
  aggregate submit, non-Claude adapter presets.

`SKILL.md` gains a short "Experiments" section pointing the agent at the
four-step user-driven loop; the `[Experiment]` label (formerly `[Experiment ·
coming soon]`) now points at this MVP for users who want to drive a local A/B.

## 0.10.2 — Custom-topic offer: per-repo only, no global opt-out

The post-audit custom-topic offer now has three options, and **none of them
globally silence the question**:

1. **Yes — customize for this repo** (recommended)
2. **Remind me next session** — defer in this repo, re-ask on the next session here (no per-repo flag set)
3. **Not for this repo — don't ask again** — silences this repo only (per-repo flag set)

Other repos still get asked. There is no longer a "never ask anywhere" option;
each repo is its own decision. The skill **no longer writes new
`~/.header/.signup-state: public-only` files**, but it still honors existing
ones from 0.10.0/0.10.1 installs for back-compat (the user can delete the file
to re-enable the offer).

Resumption: when a user picked "Yes" and didn't paste a key (`SIGNUP_STATE:
pending`), subsequent sessions re-offer with the softer "you started signup
earlier" pitch — same three options. They can keep deferring; option 3 is how
they silence the repo.

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
