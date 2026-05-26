# Experiments & Cost Analytics — design spec

Status: draft / for review. **Phase 1 (`bin/header-cost`) shipped** (v0.8.0–0.8.2; now states API-vs-subscription
cost basis). Verifiers & task mining (§11) and the `header-experiment` interface (§12) are **specified, not
built**. The runner (Phase 2+) is not yet implemented.
Aligns with the Header pre-seed thesis: *automated experimentation for AI coding agents.*
Relates to: `bin/header-audit` (hypothesis generation), `bin/header-ledger`
(`wanted`/`applied`), `bin/header-telemetry` (`experiment_interest`), the team-config layer
(`<repo>/.header/config`, the "point Header at your codebase" primitive).

---

## 0. The thesis this implements

LLM agents are non-deterministic. The best way to optimize a non-deterministic system is
**experimentation and statistical analysis** — Header is that optimization layer for AI coding agents.

The product is one loop, run continuously against a customer's agentic codebase:

> **generate hypotheses → execute experiments → keep the statistically significant wins → merge them back into the harness config.**

The non-obvious insight that makes it feasible *now*: A/B testing of code used to cost engineering
hours per variant (you'd never ask a human to write the same feature twice). Agentic coding collapses a
variant to **tokens, not hours**, so continuous experimentation becomes affordable exactly as token-cost
discipline becomes mandatory. "Mechanism beats good intentions" — automated experiments beat human
judgment loops that don't scale to daily agent change.

This doc specifies that loop: how we measure, how we run experiments, how we reach statistical
significance honestly, the architecture (local / Header-infra / hybrid), and the build order.

---

## 1. What the pitch commits us to (design constraints)

These aren't preferences — they fall out of the deck and constrain the architecture:

- **Cost measurement is the billing meter, not a feature.** The Pro tier is priced as *a share of
  realized token savings* (20-30%). We can only invoice a savings number we can defend. That makes the
  noise-floor work (§3) and the confidence intervals (§6) **revenue-critical**: if the savings figure is
  inside the noise band, the Pro tier is unbillable.
- **Two billing bases — and they change what "savings" means.** Token cost maps to value differently:
  - **API / Console (pay-per-token):** tokens → real dollars. The savings-share Pro pricing applies here,
    and on enterprise contracts. This is where the "share of realized savings" model lives.
  - **Subscription (Claude Pro \$20 / Max \$100 / \$200 a month):** flat fee, **no per-token cost**. The
    `$` is a shadow/API-equivalent number; the real constraint is **usage limits** (rolling + weekly caps),
    so the value is **headroom** — more work per period, or avoiding a tier upgrade. You can't bill a share
    of dollars that were never spent; subscription users are the **\$15/dev self-serve** wedge, sold on
    headroom, not savings-share.

  The experiment measures **tokens** either way; the **percentage** is basis-agnostic (tokens saved =
  dollars for API, headroom for subscription). Only the dollar interpretation — and therefore the pricing
  model — differs. Every figure must state its basis (the cost meter already does).
- **Hypothesis generation is the COGS.** "Our primary COGS is hypothesis generation." The audit *is* the
  hypothesis generator — it's the cost center and the top of the funnel, not a free giveaway.
- **Analysis runs on customer infrastructure.** Stated in the model ("Analysis runs on customer
  infrastructure… 70-80% gross margins"). The customer's compute/API budget runs the experiment; Header
  monetizes hypothesis generation + cross-customer aggregation. This *requires* a local/hybrid runner
  (§7) and is what produces the margin.
- **Aggregation across customers is the moat.** "More samples → higher sensitivity"; "model migrations
  and dependency upgrades benefit from learnings Header has already internalized." The proven-changes
  library (§7.3) is the one thing a single customer — or a model provider optimizing only its own
  model — structurally can't replicate. Model- and harness-agnostic by design.
- **"Merge back" requires *significance*, but significance is not the whole gate.** Statistical proof is
  mandatory; merge also requires a practical effect size, a clean safety diff, and explicit approval (§6.5).
- **Briefings are the distribution wedge, not the thesis.** The public skill's reader/audit gets Header
  installed and earns the "point at your codebase" relationship ($15/dev self-serve). Its on-thesis job
  is to **feed the experiment queue**: "new Opus dropped → run a migration experiment," "this dep has a
  cooldown-gate win." News becomes hypotheses.

**Feature ↔ pitch mapping** (what to build, and the sentence it executes):

| Capability | Pitch line | Role |
|---|---|---|
| Experiment engine + A/A + significance | "experimentation and statistical analysis"; "statistically significant wins" | The product |
| Realized-savings measurement (`header-cost`) | "share of realized token savings (20-30%)"; "ROI-positive by construction" | Billing meter |
| Evidence-gated merge-back | "merge … back into the agent's harness configuration" | Loop close |
| Hypothesis generation (the audit) | "continuously generates hypotheses"; "primary COGS is hypothesis generation" | COGS + funnel |
| Hybrid runner (analysis on customer infra) | "Analysis runs on customer infrastructure … 70-80% margins" | Margin |
| Proven-changes library (cross-customer) | "aggregation of experimental results across all customers" | Moat |
| Model-routing / migration experiments | "model migrations and dependency upgrades" | Named first learnings |
| Briefing reader | "distribution wedge via the public Header-Skill" | Wedge, not thesis |

---

## 2. Goals & non-goals

**Goal.** For a proposed harness change (delete a CLAUDE.md section, switch/route a model, add a gate,
rewrite a subagent): produce a defensible verdict — *does B reduce cost without regressing quality, and
how confident are we?* — with the `n`, the effect size, and a confidence interval strong enough to
**bill on**.

**Non-goals (v1).** Not a general ML eval platform — scoped to *agent-harness* changes. No fabricated
numbers: underpowered → say so; estimates labeled `est.` (extends the existing SKILL.md rule).

**The hard truth that shapes everything:** agent runs are **noisy** (sampling temperature,
nondeterministic tool results, prompt-cache state, silent model drift). A single A-vs-B comparison is
worthless — and a noisy savings number is unbillable. We design around noise first, comparison second.

---

## 3. Noise first: A/A before A/B

Before any A/B, run an **A/A test** — the *identical* config against itself (or one batch split randomly
into two arbitrary groups). It does three jobs:

1. **Validates the harness.** Under A/A the true effect is zero. If the pipeline reports a "significant"
   A/A difference, there's a confound (ordering, cache warmup, temporal drift) — **fix it before trusting
   any A/B, and before quoting any savings.** Most teams skip this; it's the guardrail that keeps the
   billing meter honest.
2. **Estimates the noise floor (σ)** per metric — the variance you must beat — which feeds power analysis.
3. **Reveals non-independence** — e.g. prompt-cache warmup makes run #1 systematically pricier than
   #2..N. A/A surfaces it so we randomize order or discard warmup.

Procedure: run config A `K` times per task on the v0 suite, then estimate per-task and pooled σ, compute
the **minimum detectable effect (MDE)** at 80% power / α=0.05, and check that observed A/A bias is below a
pre-registered practical threshold. A CI containing 0 is necessary but not enough; with low N it can hide a
large noise floor, and with many metrics it can fail spuriously. Also test for order/cache/time covariates.
If A/A shows practical bias or unstable variance → STOP, debug the harness. Only then run A/B.

---

## 4. What we measure

**Unit:** one *task run* = (task, arm, replicate).

**Analysis unit:** one *task* (or task block), not one replicate. Replicates within the same task are
clustered observations; treating them as independent would overstate confidence. Aggregate or model
within-task A/B deltas first, then bootstrap / test at the task-block level.

| Metric | Type | Notes |
|---|---|---|
| `input_tokens`, `output_tokens` | count | from API / agent usage |
| `cache_read_tokens`, `cache_write_tokens` | count | **track separately** — cache state dominates cost variance |
| `cost_usd` | continuous | Σ tokens × price(model, token-type); §9 price table. **This is the billed number.** |
| `latency_s` | continuous | wall-clock; turns / tool-calls as efficiency proxies |
| `success` | binary | from a **deterministic verifier** (tests pass / output matches) |
| `quality_score` | 0–1 (optional) | only when binary success is too coarse; LLM-judge or rubric |

**`cost_usd` is the "win" metric and the billing meter; `success` is the non-inferiority guardrail** —
we want cost↓ *subject to* quality not dropping.

**Measurement plumbing.** Anthropic Messages API returns `usage` per call (input / output /
cache_creation / cache_read). Cleanest if the runner drives the model via the Claude Agent SDK. Claude
Code headless: `claude -p "<task>" --output-format json` returns result + usage, or OpenTelemetry
metrics (`claude_code.token.usage`, cost). **Store raw per-run records** (never aggregate-only) so the
analysis — and any billing dispute — can be re-derived.

---

## 5. The task suite (the hard design decision)

A win is only real against a representative, reproducible task set. Layered, in build order:

- **L0 — repo-as-task (v0 for prompt-debt).** Use the project's own test suite as the verifier; the
  task is "make the change / hold the spec," success = tests still pass. For *deletion* experiments the
  suite must still exercise the harness under representative agent work; "tests pass after deletion" alone
  does not measure whether the removed prompt mattered. Deterministic, no judge.
- **L1 — curated golden tasks.** 15–30 small gradeable tasks pinned to a commit, each with an automatic
  verifier (test, regex/AST match, or rubric). The workhorse suite.
- **L2 — replayed real tasks.** Captured transcripts replayed against a pinned checkout. Most realistic,
  hardest to grade/stabilize. Later.

Pinning & isolation are part of the suite: every run executes in a clean `git worktree` at a fixed
commit, sandboxed, so external state can't leak between runs.

---

## 6. Experiment design & statistics (the "statistically significant wins" engine)

### 6.1 Pre-registration (anti-p-hacking)
The `spec.json` is written **before** running and fixes the metric(s), test, N per arm, non-inferiority
margin δ, and decision rule. The spec *is* the pre-registration. Critical when the output becomes an
invoice line.

### 6.2 Design choices that kill variance
- **Pair/block by task** — run A and B on the *same* task, analyze the within-task difference. Task
  heterogeneity is the biggest noise source; pairing removes it. Highest-leverage choice.
- **Interleave A/B in time** (A,B,B,A,…), not all-A-then-all-B — temporal/model drift hits both arms equally.
- **Randomize** task order and arm assignment; counterbalance.
- **Replicate** K× per (task, arm) — temperature can't be seeded away in the Anthropic API; beat it with replication.

### 6.3 Power → choose N
From the A/A σ and the effect you care about (e.g. ≥5% token reduction), compute N per arm for 80%
power, α=0.05. Intuition: `N ∝ (σ/MDE)²`. Token data is high-variance and right-skewed → prefer
log-transform or non-parametric tests, expect non-trivial N.

### 6.4 Tests by metric type

| Metric | Paired (preferred) | Unpaired | Report |
|---|---|---|---|
| tokens / cost / latency (continuous, skewed) | paired t on differences, or **Wilcoxon signed-rank** | Welch's t / Mann–Whitney U | median diff + **bootstrap 95% CI** |
| success (binary) | **McNemar's** | two-proportion z / Fisher's exact (small N) | risk diff + CI |
| quality_score (0–1) | paired t / Wilcoxon | Welch's t | effect size + CI |

Lead with **effect size + CI**, not the p-value. For skewed token data, **bootstrap CIs** are robust and
trivial to implement.

### 6.5 Decision rule (non-inferiority + superiority)
Merge B iff **both**:
- **Cost superiority** — upper bound of the cost-difference CI (B − A) is below 0 (genuinely cheaper).
- **Quality non-inferiority** — lower bound of the success-rate difference CI (B − A) is above **−δ**
  (not worse by more than the margin, e.g. δ = 2% absolute).

Then merge only if the effect is practically meaningful, the diff is safe/reviewable, and the user approves
the change. Anything else → "no proven win" (flagging underpowered vs genuinely flat). For experimental
savings, if Δ = B − A, the conservative savings rate is `max(0, -upper_CI(Δ))`; never bill the optimistic
tail. For Pro billing, distinguish the experiment-estimated savings rate from **realized post-merge
savings** on actual production usage volume.

### 6.6 Multiple comparisons & peeking
Many experiments/metrics at once → control false discovery with **Benjamini–Hochberg FDR**. **Don't
peek-and-stop** (inflates false positives) — default to fixed-N (§6.3); at backend scale, use always-valid
sequential inference (mSPRT / group-sequential alpha-spending) for honest early stopping.

### 6.7 Confounds → designed out

| Confound | Mitigation |
|---|---|
| Prompt-cache warmup (cold vs warm cost) | discard warmup, or measure cache tokens separately + randomize order |
| Temporal / silent model drift | interleave A/B; record model id + date/fingerprint per run |
| Order effects | randomize + counterbalance |
| External state (codebase, deps, network) | pinned commit, clean worktree per run, sandboxed tools |
| Grader noise | prefer deterministic verifiers; if LLM-judge, measure its test–retest reliability, majority of multiple judges |
| Temperature nondeterminism | replication (K runs) |

---

## 7. Architecture

New helper `bin/header-experiment` (consistent with `header-audit` / `header-ledger` / `header-repo`):

```
header-experiment define  <change>     # write spec.json (pre-registration: arms, suite, N, δ, tests)
header-experiment run      <id> [--aa] # execute the matrix (interleaved, isolated); append runs.jsonl
header-experiment analyze  <id>        # stats per §6 → result.json (effect, CI, verdict)
header-experiment report   <id>        # scorecard; record to ledger; consent-gated aggregate submit
header-experiment merge    <id>        # apply a significant win to the harness (gated; shows diff)
```

Storage (local-first, like the ledger):
```
~/.header/experiments/<id>/
  spec.json     # pre-registration: arms (A/B configs), suite ref+commit, N, metrics, δ, test
  runs.jsonl    # one raw record per (task, arm, replicate): usage, cost, latency, success, model id, price table, ts
  result.json   # analysis: per-metric effect + CI + test + verdict + power + billable-savings bound
```

**Runner core** (per `(task, arm, replicate)`): clean worktree @ pinned commit → apply the arm's config
(swap CLAUDE.md / model / gate) → invoke the agent on the task (sandboxed, tool-restricted, wall-clock +
token caps) → capture usage + verifier → append to `runs.jsonl`. The agent invocation is the
harness-specific seam (Claude Code headless / Agent SDK / generic CLI) — kept behind one adapter so Header
stays **model- and harness-agnostic** (a pitch requirement).

**Safety:** the runner executes the agent *autonomously* on tasks — real blast radius. Worktree
isolation, a tool allow-list (reuse the audit's bash-posture work), no-network where possible, and hard
time/token caps are mandatory. Merge is always gated and shows a diff.

### 7.1 Local runner
✓ Private (repo/CLAUDE.md/tasks never leave the machine). ✓ Real environment.
✗ Noisier (local hardware/network/time-of-day). ✗ Serial → slower, spends the customer's API budget.

### 7.2 Header infra
✓ Controlled env → less noise; massive parallelism → fast. ✓ A **standardized benchmark suite** →
results comparable across customers. ✗ Privacy (can't ship proprietary CLAUDE.md/repo without consent).
✗ Needs a model-API budget.

### 7.3 Hybrid (the design) — and why it produces the margins and the moat
- **Private experiments run locally / on customer infra.** Code and prompts stay put. The runner submits
  **only anonymized aggregates** — effect size, `n`, and the change *category* (e.g. "deleted
  think-step-by-step block"), never code — consent-gated, exactly like `experiment_interest` today. Aggregates
  need enough context to be reusable without leaking code: model family, harness type, verifier tier,
  ecosystem/language, task class, baseline prompt size, cache mode, and price-table version. Backend reporting
  must enforce small-cohort protections (for example k-anonymity thresholds) before surfacing cross-customer
  claims. This is the literal "analysis runs on customer infrastructure" → **Header's COGS is just hypothesis
  generation → 70-80% margins.**
- **Standardized experiments run on Header infra** against a public benchmark, for generic changes.
  Header pools these + the anonymized customer aggregates into a **proven-changes library** served back to
  the skill — the **moat**: "deleting this pattern is proven to save a median ~X% with no regression
  across the benchmark + N repos (here's the CI)." Model migrations and dependency upgrades are the first
  internalized learnings, exactly as the deck claims. More customers → more samples → higher sensitivity →
  better than any single customer (or single-model provider) could reach alone.

---

## 8. MVP: the prompt-debt deletion wedge

Build the smallest end-to-end loop first — it sidesteps the two hardest problems (task suite + quality metric):

1. **Candidate:** a CLAUDE.md/AGENTS.md section the audit already flagged as cargo-cult debt (hypothesis generation, free).
2. **Arms:** A = current harness; B = section removed.
3. **Suite (L0/L1):** the repo's golden tasks with deterministic verifiers.
4. **Metric:** total cost (billed/win) + success rate (non-inferiority guardrail, small δ).
5. **Design:** paired by task, interleaved, K replicates (K from the A/A power analysis).
6. **A/A first:** validate harness + estimate σ + set N.
7. **Decision:** merge iff cost-CI favorable AND success non-inferior within δ; else keep + "no proven win."

Why first: deletion is low-risk, the candidate is auto-detected, the verifier is binary, and a *null*
quality result **is** the win (same quality, fewer tokens) — the cleanest possible first billable savings.
Model-routing (harder quality measurement) comes after.

---

## 9. Cost analytics + model-routing (#5)

**`header-cost` — the billing meter and the opportunity finder.** Estimate $/period from usage history
(tokens × price table), broken down by model and task class. Surfaces targets ("you run Opus for
everything; here's the spend") *and* produces the realized-savings figure the Pro tier bills on. Inputs:
usage from the runner / OTEL / ledger; a price table (input/output/cache prices per model — served by
Header so it stays current, or bundled + update-checked).

**Routing recommendations → experiments.** Classify task types (boilerplate / test-gen / refactor vs
architecture / debugging) and recommend a cheaper model for low-stakes classes, with a $ estimate. The
elegant part: a routing rec *is* a hypothesis — "route boilerplate to Haiku → −X%; prove it" — so the
experiment engine runs A (all-Opus) vs B (routed), measures cost + quality, and only merges if quality
holds (§6.5). #5 needs no separate proof machinery; it's the **second experiment type** after prompt-debt
and maps directly to the "model migrations" learning the moat names.

**Output basis (shipped).** `header-cost` labels every figure as **API (pay-per-token) rates** and warns
that subscription users (Pro \$20 / Max \$100 / \$200) don't pay them — for them the `$` is a shadow number
and the lever is **usage-limit headroom** (see §1). A future **subscription mode** would translate token
volume into "% of your weekly cap consumed" / "headroom freed" given the plan's limits; until then the
**percentage** savings carries across both bases and is the honest cross-mode number.

---

## 10. Build order (sequenced by pitch consistency)

Engineering pragmatism and the thesis happen to agree. Each step is the next sentence of the pitch made real.

1. **Realized-spend measurement (`header-cost`)** — ✅ **shipped (v0.8.0–0.8.3).** The billing meter; proves
   the wedge's value with no runner yet; reads usage JSONL or raw Claude Code transcripts. `report` (measured
   spend by model — cache priced by real 5m/1h duration, legacy Opus priced apart), `cost`, `prices`,
   `refresh`. It reports **measured numbers only**: `savings` no longer projects (a price re-rating of the
   same tokens is a guess) — it just points at experiments. *Without a trustworthy number there is no Pro
   revenue, so the meter must not emit guesses.* Next: feed it real usage automatically (OTEL / a usage log)
   and wire per-model spend into the audit so routing *candidates* (to be proven, not projected) surface.
2. **A/A harness + measurement plumbing** — the foundation: capture usage, isolate runs, estimate σ,
   validate the harness. This is what makes "statistically significant" real (and billable).
3. **Prompt-debt experiment (MVP) + significance-gated merge-back** — first end-to-end loop, closing on
   the deck's "merge wins back into the harness configuration."
4. **Cross-customer proven-changes library** — the moat. Pull this *earlier* than pure eng-sequencing
   suggests, because aggregation is the defensibility vs Cursor/Kiro/model providers. Lead with the two
   learnings the deck names: **model migrations + dependency upgrades.**
5. **Org dashboard + value receipts** — the Pro-tier sell/retain surface: how a 30-engineer team's leader
   sees "saved $X, billed 0.25X" (ROI-positive by construction). Buyer = engineering leaders; tier = team-priced.
6. **Continuous operation (audit-cron / experiment-cron)** — the "*continuously* generates… executes."
   Turns the one-shot into the standing optimization layer. Builds on the server-side briefing schedule already shipped.

Distribution stays upstream of all of this: the **briefing reader** (the wedge) keeps feeding hypotheses
into step 3+ — new models and dep advisories become experiments.

---

## 11. Verifiers & task mining (the #1 hard problem)

Everything above assumes a `verify()` that, for a given task, answers *did this agent run succeed?* —
objectively, reproducibly, cheaply (it runs hundreds of times), faithfully, and **on an arbitrary customer
codebase** without a human hand-writing a grader per task. That last clause is the hard part. The reframe
that makes it tractable:

> **You don't author verifiers. You mine them.** A real codebase already ships its own correctness oracle —
> the **test suite, the build, the type-checker, the linter**. The job is to *manufacture tasks whose oracle
> already exists*, and the richest source is the customer's **git history**. This is the SWE-bench
> construction pointed at the customer's own repo.

### Worked example — git-history reversal → task + oracle
Commit `a1b2c3` fixed a null-deref: it touched `src/auth.ts` **and** added 3 cases to `auth.test.ts`.
1. Check out the **parent** (`a1b2c3^`).
2. Apply **only the test file** from the child commit.
3. Run the suite → those 3 tests **fail** (`FAIL_TO_PASS`); everything else stays **green** (`PASS_TO_PASS`).
4. Hide future git history from the agent (synthetic/shallow checkout, no child commit reachable via `.git`).
5. **Lock the test files read-only.** Task = *"make the suite pass."*
6. Run the **Opus arm** and **Sonnet arm** in separate sandboxes.
7. **Oracle (one objective bit):** target tests go FAIL→PASS **AND** no PASS_TO_PASS regression **AND**
   build + typecheck clean.

`random() < 0.94` becomes `tests_pass AND no_regressions AND builds`. Nobody hand-wrote it — the human who
made that commit already did. **Every commit touching code + tests together is a task/oracle pair**; a repo
with history is a factory of them.

### The verifier ladder (use the strongest tier a task supports)
- **Tier 1 — objective oracle (default):** the repo's own tests / build / typecheck / lint. Tasks from
  git-history reversal, CI red→green commits, "refactor X, suite stays green." Objective, cheap,
  harder to game when test files and verifier commands are controlled. Bounded by what tests cover.
- **Tier 2 — differential / equivalence (no golden answer needed):** grade **both arms against the same
  gate** — does B's diff also compile, typecheck, keep the suite green? For refactors: run the *existing*
  tests against both outputs, or property-test the changed function and diff A-vs-B behavior. Symmetric and
  fair; "passes gates" ≠ "elegant."
- **Tier 3 — LLM judge (fallback for what tests can't capture):** docstrings, explanations, open-ended
  generation. Make it **reference-based** (compare to the human's merged answer from git) and **blind
  pairwise** (judge sees A and B unlabeled → better/tie; pairwise beats absolute scoring). Then **validate
  the judge**: ensemble + majority, measure test-retest agreement, control position/verbosity/self-preference
  bias. Covers everything; noisy, biased, expensive — never the default.
- **Tier 4 — process guardrails (secondary signal, not a verdict):** finished without error, turn count,
  touched only relevant files, repo still runnable.

Hierarchy in practice: **Tier 1 wherever tests exist; Tier 2 for refactors/migrations; Tier 3 only for the
uncovered remainder, flagged as soft.**

### A/A earns its keep here (not circular in the real system)
Run the oracle repeatedly on the **unchanged** state. Any test that isn't deterministic (network, time,
ordering, race) gets **quarantined out of the oracle** — automated flaky-test detection. A/A also measures
the environment's true noise floor, which sizes replication. Flaky tests are the #1 thing that silently
corrupts a code verifier; A/A is the defense.

### Per-task runner pipeline
```
for each mined task, for each arm (A/B), K times:
  1. synthetic/shallow checkout at the pinned commit, in an isolated sandbox (container)
  2. install deps + detect build/test commands  ← reuse header-audit ecosystem detection;
     better, read the CI config (.github/workflows, .gitlab-ci.yml) — it already encodes
     exactly how to build + test this repo
  3. baseline: run suite/build → record the green set (PASS_TO_PASS); quarantine flaky tests
  4. apply the task (revert impl, keep + lock tests); run the agent → capture real usage + diff
  5. verify outside the agent-controlled shell: target FAIL→PASS? PASS_TO_PASS still green? build/types/lint clean?
  6. teardown the worktree
```

### Hard parts (not solved — scope honestly)
- **Coverage.** Weak tests → thin Tier 1 → forced into noisy Tier 3. You can only prove what the repo can
  verify. (Also a wedge: the audit flags low coverage; test-bootstrap helps.)
- **Reproducible environments.** Building/testing an arbitrary repo (services, DBs, secrets, monorepos) is
  genuinely hard; CI config is the best map; flaky tests poison the oracle → A/A quarantine is mandatory.
- **Reward hacking.** "Make the test pass" invites deleting/hardcoding. Mitigations: **lock test files**,
  hide future commits, run verification outside the agent-controlled shell, reject unexpected build/test config
  edits, enforce **PASS_TO_PASS**, keep **hidden held-out tests**, diff-sanity checks (did it just `return 42`?).
- **Cost.** suite × tasks × replicates × arms is expensive (compute + tokens). A/A power analysis sizes K
  to the minimum; gate on "expected savings > experiment cost."
- **Privacy.** Runs on customer code → must run on customer infra (the COGS/margin story); only anonymized
  aggregates leave.
- **"Tests ≠ all quality."** Tier 1 proves *correctness on covered behavior*, not maintainability / latency
  / taste. State the scope; broaden with Tier 3 + human spot-checks; don't overclaim.

### Verifier MVP (first build, after `header-cost`)
1. One ecosystem (the design partner's). 2. **Git-history miner**: commits touching source+tests where the
new tests fail on the parent; cap scope (≤ N files); keep ~30–50. 3. **Tests-oracle verifier only** (defer
Tier 3). 4. Sandbox + CI-config-driven build/test; **A/A flaky-test quarantine** + noise calibration.
5. Then the **A/B**: Opus vs Sonnet on the mined slice, real usage, real pass/fail → the verdict shape from
the simulation, now measured.

One-liner: **the verifier is the customer's own CI; the tasks are their own git history played back.** You're
not grading the model's taste — you're checking whether the cheaper model's diff still clears the bar the
team already trusts.

---

## 12. `header-experiment` interfaces (spec — NOT yet built)

Spec only — no implementation in this version. New helper `bin/header-experiment`, consistent with the other
`bin/` tools, local-first, runs on customer infra. Four cooperating pieces: **miner → spec → runner →
analysis**, with a pluggable **verifier**.

### CLI surface
```
header-experiment mine    [--repo DIR] [--ecosystem auto] [--max-files N] [--limit N]
                          # scan git history → emit candidate task specs (tests-bearing commits)
header-experiment define  <change>          # author an experiment: arms (A/B), task set, N, δ, tests
header-experiment run     <id> [--aa] [--k N] [--sandbox docker]   # execute matrix; append runs.jsonl
header-experiment analyze <id>              # stats per §6 → result.json (effect, CI, verdict, power)
header-experiment report  <id>              # scorecard; ledger; consent-gated aggregate submit
header-experiment merge   <id>              # apply a significant win (gated; shows diff)
```

### Task spec (one per mined/curated task) — `task-specs.jsonl`
```json
{
  "id": "auth-nulldef-a1b2c3",
  "repo_commit": "a1b2c3^",                     // pinned base state
  "kind": "git-reversal",                        // git-reversal | refactor-equiv | curated | synthetic
  "apply": { "checkout": "a1b2c3^", "patch_from": "a1b2c3", "patch_paths": ["auth.test.ts"] },
  "lock_paths": ["auth.test.ts"],                // agent may not edit these
  "verifier": "tests-oracle",                    // registry key (see below)
  "oracle": { "fail_to_pass": ["auth.test.ts::null_token"], "pass_to_pass": "baseline" },
  "build": ["npm ci"], "test": ["npm test"],     // from CI config / audit detection; null = auto-detect
  "scope_files": 2, "est_minutes": 3
}
```

### Verifier interface (a registry; runner stays agnostic)
```
verify(repo_at_commit, task_spec, agent_diff) -> {
  passed: bool,                 // the objective bit (Tier 1/2) or judged win (Tier 3)
  score:  float|null,           // optional graded quality (0..1)
  signals: { build:bool, typecheck:bool, lint:bool, fail_to_pass:int, regressions:int, turns:int },
  flaky_quarantined: [..],      // tests dropped during A/A calibration
  verifier: "tests-oracle"      // tests-oracle | build-gate | equivalence | llm-judge
}
```
Implementations: `tests-oracle` (T1), `build-gate`/`equivalence` (T2), `llm-judge` (T3, reference+pairwise,
ensemble). New task types add a verifier without touching the runner.

### Arm / config (what A and B actually are)
```json
{ "A": { "model": "claude-opus-4-7",   "harness": "default" },
  "B": { "model": "claude-sonnet-4-6", "harness": "default" } }   // or harness deltas: CLAUDE.md edit, gate, subagent
```

### Runner contract (per task × arm × replicate)
- Isolation: fresh `git worktree` at `repo_commit` in a sandbox (container; tool allow-list reusing the
  audit's bash posture; no-network where possible; wall-clock + token caps). Never edit `lock_paths`.
- Agent adapter (one seam, keeps Header **model/harness-agnostic**): Claude Code headless
  (`claude -p --output-format json`) | Claude Agent SDK | generic CLI. Captures real `usage` (→ `header-cost`).
- Order: **interleave** arms in time; randomize task order; **pair by task** (§6.2).

### Artifacts (local-first, like the ledger)
```
~/.header/experiments/<id>/
  spec.json          # pre-registration: arms, task set ref, N, δ, metric, test (frozen before running)
  task-specs.jsonl   # the mined/curated tasks
  runs.jsonl         # one raw record per (task, arm, replicate): usage, cost, latency, verifier result, price table
  result.json        # analysis: per-metric effect + CI + verdict + power + billable-savings bound
```

### Reuse / dependencies
- `header-audit` → ecosystem + build/test detection, bash-tool sandbox posture.
- CI config → the authoritative build+test recipe.
- `header-cost` → real usage capture + cost basis (API vs subscription).
- `header-ledger` / `header-telemetry` → record outcomes + consent-gated aggregate submit (the moat).

**Status: design only.** Build order: this lands as Phase 2/3 in §10, *after* `header-cost` (shipped) and
the A/A harness. The verifier MVP (§11) is the first runnable slice.

---

## 13. Open questions / risks

- **Billing trust.** Because we invoice on realized savings, the savings number must survive a customer
  audit. Conservative-bound billing (§6.5), raw run records (§4), and a clean A/A (§3) are the defenses.
  Get this wrong and the Pro tier is disputed, not just inaccurate.
- **Verifier coverage (was the #1 risk — now §11).** Addressed by "Verifiers & task mining": mine the repo's
  own tests/build/types as the oracle, reverse test-bearing git commits into tasks, fall back to a *validated*
  LLM judge only for the uncovered remainder. Residual risk: repos with weak tests limit what can be proven,
  and LLM-judge reliability must itself be measured.
- **Cost of experimenting.** Replication burns tokens (the customer's). Need budget caps + an
  "expected-savings > experiment-cost" gate. Header infra amortizes standardized experiments across customers.
- **Sandbox blast radius.** Autonomous agent runs on tasks need real isolation; a bad experiment must not
  damage the repo.
- **Privacy of standardized runs.** The shared benchmark must be genuinely generic; never require shipping
  customer code. The hybrid split (§7.3) is the answer.
- **Stat honesty at scale.** Many customers × many experiments × peeking = false-discovery minefield.
  FDR + fixed-N, or always-valid sequential, from day one on the backend.
