# Experiments & Cost Analytics — design spec

Status: draft / for review. **Phase 1 (`bin/header-cost`) shipped** in v0.8.0; the runner (Phase 2+) is not yet built.
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
- **"Merge back" is gated on *significance*, not on a risk heuristic.** The merge step ships
  statistically significant wins (§6.5), full stop.
- **Briefings are the distribution wedge, not the thesis.** The public skill's reader/audit gets Header
  installed and earns the "point at your codebase" relationship ($15/dev self-serve). Its on-thesis job
  is to **feed the experiment queue**: "new Opus dropped → run a migration experiment," "this dep has a
  cooldown-gate win." News becomes hypotheses.

**Feature ↔ pitch mapping** (what to build, and the sentence it executes):

| Capability | Pitch line | Role |
|---|---|---|
| Experiment engine + A/A + significance | "experimentation and statistical analysis"; "statistically significant wins" | The product |
| Realized-savings measurement (`header-cost`) | "share of realized token savings (20-30%)"; "ROI-positive by construction" | Billing meter |
| Significance-gated merge-back | "merge … back into the agent's harness configuration" | Loop close |
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
the **minimum detectable effect (MDE)** at 80% power / α=0.05, and assert the A/A difference CI contains 0
for every metric. If not → STOP, debug the harness. Only then run A/B.

---

## 4. What we measure

**Unit:** one *task run* = (task, arm, replicate).

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
  suite is just "run the golden tasks, confirm no regression." Deterministic, no judge.
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

Anything else → "no proven win" (flagging underpowered vs genuinely flat). The **billed savings = the
measured cost-difference point estimate, discounted to the conservative bound of its CI** — never bill the
optimistic tail.

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
  runs.jsonl    # one raw record per (task, arm, replicate): usage, cost, latency, success, model id, ts
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
  think-step-by-step block"), never code — consent-gated, exactly like `experiment_interest` today. This
  is the literal "analysis runs on customer infrastructure" → **Header's COGS is just hypothesis
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

---

## 10. Build order (sequenced by pitch consistency)

Engineering pragmatism and the thesis happen to agree. Each step is the next sentence of the pitch made real.

1. **Realized-savings measurement (`header-cost`)** — ✅ **shipped (v0.8.0).** The billing meter; proves the
   wedge's value with no runner yet; reads usage JSONL or raw Claude Code transcripts. `report` (spend by
   model), `savings` (routing projection, labelled a projection), `cost`, `prices`. *Without a trustworthy
   savings number there is no Pro revenue.* Next: feed it real usage automatically (OTEL / a usage log) and
   wire the per-model spend into the audit so routing opportunities surface proactively.
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
   Turns the one-shot into the standing optimization layer. Builds on the briefing/audit cron already shipped.

Distribution stays upstream of all of this: the **briefing reader** (the wedge) keeps feeding hypotheses
into step 3+ — new models and dep advisories become experiments.

---

## 11. Open questions / risks

- **Billing trust.** Because we invoice on realized savings, the savings number must survive a customer
  audit. Conservative-bound billing (§6.5), raw run records (§4), and a clean A/A (§3) are the defenses.
  Get this wrong and the Pro tier is disputed, not just inaccurate.
- **Quality metric beyond pass/fail.** Routing/model changes need finer measurement than binary tests;
  LLM-judge reliability must itself be measured. The MVP dodges it on purpose; it's the gating problem for L2.
- **Cost of experimenting.** Replication burns tokens (the customer's). Need budget caps + an
  "expected-savings > experiment-cost" gate. Header infra amortizes standardized experiments across customers.
- **Sandbox blast radius.** Autonomous agent runs on tasks need real isolation; a bad experiment must not
  damage the repo.
- **Privacy of standardized runs.** The shared benchmark must be genuinely generic; never require shipping
  customer code. The hybrid split (§7.3) is the answer.
- **Stat honesty at scale.** Many customers × many experiments × peeking = false-discovery minefield.
  FDR + fixed-N, or always-valid sequential, from day one on the backend.
