# Roadmap

Tracked follow-ups and deferred decisions. See [CHANGELOG.md](CHANGELOG.md) for what's shipped.

## Planned

### Experiments engine (`header-experiment`)

Header's north star: an optimization layer for AI coding agents. The loop —
**generate hypotheses → run experiments → keep the statistically significant wins →
merge them back into the harness config** — run continuously against a customer's
codebase. Feasible now because agentic coding collapses an A/B variant from
engineering-hours to **tokens**, so continuous experimentation gets affordable exactly
as token discipline becomes mandatory.

It builds on what's already shipped: the **briefing reader** (the wedge that feeds
hypotheses — new models, dependency advisories), **`header-cost`** (the
measurement / billing meter), and an **`header-experiment` MVP (beta, local-only)**
that closes the audit → experiment → applied-change loop in code, not just in prose:

- **`new`** (0.11.1, extended 0.12.0) — audit-aware scaffolder.
  - `--kind prompt-debt-deletion --file F --lines L1,L2,...` — the §8 wedge.
    v0.12.0 adds an up-front **magnitude estimate**; <5% changes surface
    `[Apply with review]` and cheaper-experiment levers (don't burn tokens
    proving a tiny effect).
  - `--kind clause-add --file F --after-line N --text "..."` (0.12.0) — INSERTION
    experiments for behavior-change cases (mandatory-skill rules, delegation
    toggles, fast-mode instructions, framework-migration patches).
  - `--kind model-swap` generates a two-arm model spec. Generic `--arm` flow for
    everything else.
- **`define / validate / run / analyze / report`** (0.11.0; `run`'s cost gate extended
  in 0.12.0 to speak both billing modes + the cost-vs-magnitude rule + cheap-experiment
  levers) — worktree-isolated runs, paired-by-task bootstrap CIs, A/A noise-floor mode,
  §6.5 cost-superiority + success non-inferiority decision rule, conservative savings rate.
- **`merge`** (0.11.1) — applies arm B's overrides to the repo after a B-wins
  verdict (refuses other verdicts unless `--force`). Shows the unified diff first,
  asks for confirmation, prints a suggested `git commit` with the
  `Header-Audit-Finding:` trailer when the experiment originated from an audit
  finding (`--ledger-key`). Doesn't auto-commit — user retains the final say.

**Next on this track (not yet built):**

- **Verifiers & task mining from git history** (§11 of the design) — the hardest
  open problem. Turn the customer's own test suite into the oracle; mine
  FAIL_TO_PASS commits into task specs so users don't hand-author task prompts. The
  current MVP requires the user to write the prompt + name the verify command.
- **Per-experiment ephemeral infra (`setup:` / `teardown:` lifecycle)** — the next
  big capability, and the one that unblocks infra-dependent mandates (visual-verify,
  curl-self-check). `worktree_include` handles *files*; stateful experiments need
  *services*: provision an isolated DB (Neon branch, throwaway Postgres) per
  experiment, inject its connection string into each run's worktree env, and
  **guarantee teardown** (orphaned branches cost money and accrue). Open design
  questions: **granularity** — read-only tasks share one branch; write tasks need
  isolation per *run* (task×arm×rep), or arm A's writes contaminate arm B and
  replicates contaminate each other, which multiplies branch count; **seeding**
  (snapshot vs. migrate-from-scratch); and **cleanup on crash/interrupt**. Bonus:
  tool-managed provisioning removes the hand-injected-`.env` ambiguity that makes
  "is this the throwaway DB or prod?" a live footgun today.
- **Cost-axis non-discrimination detection** — the discrimination warning guards
  the *success* axis (does the task exercise the trimmed instruction?). Its twin on
  the *cost* axis: if the run adapter never *performs* the mandated expensive work
  (a one-shot headless `claude -p` won't boot a server + drive a browser), arm A's
  cost collapses onto arm B's → a false "the mandate is free." The runner should
  flag a per-arm cost delta that's implausibly small for a mandate that should be
  expensive.
- **Guardrail-value mode** — "is this mandate earning its cost?" decomposes into
  *cost* (cheap: measure one execution) and *benefit* (tail-risk insurance —
  unmeasurable at small N; a rare-event rate needs many realistic tasks or
  historical bug replay, not a 1×4 A/B). The skill should make "measure the cost
  directly, reason about the benefit qualitatively" the **default recommendation**
  for guardrail-value questions, instead of scaffolding an underpowered A/B.
- **σ-based power analysis** — A/A surfaces the per-metric noise floor; use it to
  size N (replicates × tasks) for a chosen MDE. Today the `<5 paired tasks →
  underpowered` cutoff is a hand-picked heuristic, not power-driven.
- **Cross-customer proven-changes library** — consent-gated aggregate submit of
  effect size + change category (no code, no paths); pulled back into the audit as
  "deleting this pattern is proven to save ~X% across N repos." This is the moat.
- **LLM-judge verifier** (Tier 3 of §11) — for tasks the repo's tests don't cover.
  Reference-based, blind-pairwise, judge-validation required.
- **`header-experiment run` schedule integration** — close the loop with the
  briefing schedule: "new Opus dropped → queue a migration experiment."
- **`tokens × header-cost` cost fallback** — current runner reads claude's
  `total_cost_usd`; if that field disappears in a future Claude Code, cost falls
  to 0 silently. Should fall back to computing from usage tokens × price table.

Full design — measurement, the A/A noise floor, statistics, verifiers & task mining,
the local / Header-infra / hybrid architecture, build order, and the CLI spec — lives
in [docs/experiments-design.md](docs/experiments-design.md).

## Deferred

### Claude Code `/plugin` marketplace distribution

**Status:** deferred (2026-05-22). Install today is `npx skills` (README Option A) plus the `curl | sh` / clone paths; updates run through the skill's own version-endpoint check.

Supporting `/plugin marketplace add Header-inc/Header-skill` was evaluated and held off:

- **No auto-update benefit by default.** Third-party marketplaces have auto-update **off by default** in Claude Code — users would have to opt in per-marketplace, so it doesn't beat our existing updater out of the box.
- **Conflicts with our self-update.** A plugin installs to `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` — a different location from `~/.claude/skills/header/`, where `install.sh`, `npx skills -g`, and the self-update all write. Installing both would duplicate the skill and split its command namespace (`/header` vs `/header:…`).
- **Our updater is more capable here.** `bin/header-update-check` gates on the Header API's minimum-supported version (`UPDATE_REQUIRED`); the marketplace has no API-version gate.

**To adopt later:**
1. Add `.claude-plugin/marketplace.json` (+ a `plugin.json`) pointing at the `header` skill.
2. Teach the skill to detect plugin-mode (e.g. when its own directory resolves under `~/.claude/plugins/`) and **stand down its self-update** there, deferring to the marketplace.
3. Document `/plugin marketplace add` + `/plugin install` as a Claude Code option, noting users must enable marketplace auto-update for it to refresh on its own.
