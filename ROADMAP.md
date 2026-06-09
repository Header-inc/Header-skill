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
- **Ephemeral-infra lifecycle + discrimination/cost-axis/guardrail** (0.12.x–0.13.0) —
  `setup:` / `teardown:` / `setup_scope:` provision an isolated DB/branch per
  experiment (or per run for write isolation), inject its connection info into the
  adapter + verifier, and tear it down via a guaranteed `EXIT`/`INT`/`TERM` trap.
  `validate`/`run` warn when a prompt-debt deletion can't discriminate (success
  axis); `report` warns on the cost axis (arm A not measurably costlier → the
  adapter may not have performed the mandate); mandate deletions surface the
  **guardrail-value** recommendation. Plus soft power tiers, replicate-level A/A,
  `worktree_include`, and pre-spend honesty (degenerate-CI + the measured A/A
  noise floor surfaced at the gate).
- **Git-history task mining + tests-oracle verifier** (0.16.0, §11 — *the
  keystone*) — `header-experiment mine` scans the repo's history for fixes
  touching source + tests, validates each by re-applying the fix's tests at the
  parent and running the suite (keeping the FAIL_TO_PASS ones), and writes a
  runnable experiment (default: a model-swap A/B). The runner gained per-task
  base `commit` + `apply_from`/`apply_paths`/`lock_paths`: it applies the fixing
  commit's tests before the agent and **re-locks them before grading**, so the
  oracle can't be gamed by editing the test. Removes the last hand-authoring
  friction — no task prompts, no verify commands — and is the on-ramp for
  model-routing experiments at scale.

**Next on this track (not yet built):**

- **Tool-managed infra provisioning** (the next step on the shipped `setup:`/
  `teardown:` lifecycle) — a `--kind` / provider helper that creates+drops a Neon
  branch (or docker Postgres) for you, so users don't hand-write the `setup:`
  command or eyeball connection strings. Open design questions carried over:
  **seeding** (snapshot vs. migrate-from-scratch) and surfacing orphaned-branch
  cleanup if a crash outruns the teardown trap.
- **σ-based power analysis** — A/A surfaces the per-metric noise floor; use it to
  size N (replicates × tasks) for a chosen MDE. Today the `<5 paired tasks →
  underpowered` cutoff is a hand-picked heuristic, not power-driven.
- **Cross-customer proven-changes library** — **client side shipped (0.23.0)**:
  `header-experiment aggregate` submits the anonymized effect record (consent-gated,
  unauthenticated by design — no identity/repo/prompts/free text on the wire;
  `aggregate_submit` config, personal-only), and 6-field `patterns.tsv` rows flow
  back as `PROVEN` audit lines ("deleting this pattern is proven to save ~X%
  across N repos"). **Server side pending**: the `POST /api/v2/experiments/aggregate`
  endpoint, k-anonymity cohort protection, and publishing pooled results into
  briefing-supplied proven rows. This is the moat.
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

### Engine adoption — "should you use this model in your harness?" (v0.18.0, the launch cut)

**Status:** locked for build (2026-06-01). Launch instance: **Opus 4.8**. Full spec in
[docs/engine-adoption-design.md](docs/engine-adoption-design.md).

The first-class motion for a new model release, and the realization of the *"new Opus dropped →
queue a migration experiment"* schedule-integration bullet above. Two halves:

- **The card (rung 1) — repo-independent.** `/header opus-4.8` surfaces a grounded **adoption
  verdict**, personalized from installation-level signals (current model/effort from settings,
  realized spend from `header-cost` over `~/.claude`) — runs with no repo and no key. Content is a
  **bundled, briefing-shaped snapshot** cut from the Opus 4.8 System Card (same render path as a
  live briefing, so a future live topic is a drop-in swap). It is an explicitly-labeled
  *projection*; the verdict is still earned on a repo.
- **The proof (rung 3) — `header experiment opus-4.8`.** Mines the repo's FAIL_TO_PASS history and
  runs a **model + effort sweep** (A = the user's *actual* pinned current engine, B = 4.8 `@high`,
  C = 4.8 `@xhigh`) to find the cheapest effort that's non-inferior — the under-covered lever the
  System Card surfaces (*min-effort 4.8 ≈ max-effort 4.7* on SWE-bench Pro).

New mechanics it adds to the engine: an arm **`effort:`** field threaded as `--effort` (symmetric to
`--model`), a pinned control, a new **`engine-swap`** kind (`detect_kind` for same-model/diff-effort
arms), `merge` writing `model`+`effortLevel` for persistable wins, and a **`MODEL-UPGRADE`** audit
line (opportunity, distinct from `MODEL-STALE` debt). **Client-only — no backend changes** (the sync
endpoint already treats new `kind` values as labels). Fast-follows: an `ultracode` arm, a live
adoption briefing, and a dashboard effort column.

### Determinism rails (guardrails) — the audit's constructive axis

The reductive audit removes prompt-config debt; this adds guardrails that make
AI-written code reliable. Thesis: a non-deterministic agent forgets to run
things, so a `CLAUDE.md` "always run X" line is a *bet* paid for in tokens every
turn — promoting it to a guardrail is cheaper *and* more reliable (delete *or
promote*). Openly opinionated (conviction, not an A/B), surfaced as `[Apply with
review] (opinionated)`.

- **Detection + scaffolds** (0.21.0) — `header-audit rails` detects three rails
  (`precommit-gate`, `test-ratchet`, `compound-memory`) + the delivery context;
  `header-audit rail <name>` prints the stack-adapted artifact from
  `header/scaffold/`. Dual delivery (git-native + Claude Code `PreToolUse`) from
  one shared gate script, with the propagation tradeoff explained at install.

**Next on this track (not yet built):**

- **Confidence self-assessment gate** — a per-commit 1–100 self-score (warn, not
  block) that forces the agent to surface uncertainty instead of burying it.
- **Push / protected-branch guard** — hook-layer enforcement (auto-mode can
  bypass `permissions.ask`), the active complement to the `SECURITY bash` posture
  the audit already reads.
- **Agent-actionable hook-message lint** — score *existing* hooks on whether
  their failure output is agent remediation vs. a human diagnostic.
- **Ratchet coverage** beyond python / npm / go (rust, ruby test-fn patterns).

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
