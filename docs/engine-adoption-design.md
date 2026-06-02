# Engine adoption — "should you use this model in your harness?" — design spec

Status: **locked for build** (2026-06-01). Launch instance: **Opus 4.8**. Target: skill **v0.18.0**.

The header skill already audits *model choice* (`header-audit` emits `MODEL` / `MODEL-STALE`) and
already proves harness changes by experiment (`header-experiment`, the `model-swap` kind, the
`mine` keystone). This spec adds the missing first-class motion: when a new model ships, answer
**"should you move your coding harness to it?"** — grounded, personalized, and provable — without
requiring the user to be in a repo to *ask*.

It is a **client-only** feature. Nothing in this spec changes the backend (see §2).

## Decisions locked

The forks resolved in design discussion (do not relitigate during build):

1. **Product shape — staged, card → proof.** A repo-independent *adoption card* (rung 1) surfaces
   instantly; its CTA hands off to the existing experiment runner for the real verdict (rung 3).
   No bundled "standard battery" task pack (rung 2 was considered and dropped — it proves the
   engine on generic code, not the user's, and reads as a mini-benchmark).
2. **Proof arm — model + effort sweep**, not model-only. The control is the user's *actual*
   current engine; treatment arms add Opus 4.8 at `high` and `xhigh` (see §5).
3. **Repo line — the card is repo-independent; the verdict is earned on a repo.** "Independent of
   git repo" applies to the *card* (an explicitly-labeled projection, personalized from
   installation-level signals), not to the proof. See §1.
4. **Verdict stance — personalized by detected engine** (§4.3), never a generic recommendation.
   Keeps the skill out of projection-land where it counts and off the "benchmark recap" path.

---

## 0. Why this exists, why now

The model-adoption question is **universal and time-sensitive**: the day Opus 4.8 ships, every
Claude Code user faces "do I switch?" regardless of which repo they're in. It is also the one
audit question header *can't* currently answer well — `MODEL-STALE` only fires on genuinely
superseded tiers (≤ Opus 4.1), so a 4.7 → 4.8 move is invisible to the audit. 4.7 → 4.8 is not
*debt*; it is an *opportunity*. This feature surfaces opportunity and routes it to proof.

Two facts from the primary source make it more than a benchmark recap:

- **Same price** ($5 / $25 per Mtok, unchanged from 4.7) — so the decision is never "is it worth
  more money," it is "does it behave better on *my* work at the effort I'll actually run."
- **Effort is the real lever** (§3) — the under-covered finding that header is uniquely equipped to
  exploit, because it already owns a cost meter (`header-cost`) and a measurement loop.

## 1. The fidelity ladder — what "prove it" means

A coding harness is two layers: the **engine** (model + effort, lives in `settings.json`,
*repo-independent*) and the **fit** (CLAUDE.md, tools/MCP, hooks, the user's task distribution,
*repo-dependent*). "Should you use Opus 4.8" is an *engine* question — exactly the repo-independent
slice. The feature serves the highest rung available:

| Rung | What runs | Proves | Repo? | This spec |
| --- | --- | --- | --- | --- |
| **1 · Card** | grounded verdict from the System Card snapshot + the user's own engine/spend | population-level evidence; *a labeled projection* | no | §3, §4 |
| 2 · Bundled pack | *(considered, dropped)* | engine as a controlled proxy | no | — |
| **3 · Repo-mined** | `header-experiment mine` → engine-swap A/B/C on the user's FAIL_TO_PASS history | engine **and** fit on the user's distribution | yes | §5 |

The card is a projection and is labeled as one; the *verdict* is still earned on a repo. That keeps
the "prove it, don't project it" thesis intact while still giving the user something that runs
anywhere on launch day.

## 2. Scope: client-only. Zero server changes.

This repo is the client (bash skill + docs). The backend (briefing generation, experiment
dashboard) is a separate system and is **untouched** by the launch:

- **Card content** ships as a **bundled snapshot** in `header/`, cut with the release — the skill's
  native distribution mechanism (a release timed to the model launch; a fresh snapshot when the
  next model ships). No live briefing required.
- **Personalization** reads installation-level signals already available locally: current model +
  effort from settings, realized spend from `header-cost` over `~/.claude` transcripts.
- **Effort sweep / engine-swap / scaffolder / merge / `MODEL-UPGRADE`** are bin + SKILL.md changes.
- **Experiment sync** rides the existing endpoint unchanged. Per `docs/experiments-sync-api.md`:
  *"Nothing executes server-side… store it, show it,"* and the `kind` field *"may carry other
  values if a future client sets a precise kind — treat as a label."* Emitting `kind:"engine-swap"`
  and an arm `effort` is forward-compatible by the contract's own words.

Two **optional fast-follows** touch the backend, neither blocking launch (scope with whoever owns
it): (a) a live auto-refreshing adoption briefing in place of the bundled snapshot — content
published through the existing pipeline, not new endpoints; (b) dashboard polish to render the
`effort` dimension. Both are pure upside.

## 3. Primary-source snapshot — Opus 4.8

Source: **System Card: Claude Opus 4.8**, May 28 2026 (244 pp). Standard benchmark config =
*adaptive thinking at max effort*, averaged over 5 trials, context ≤ 1M. This section is the **seed
for the bundled data file** (§4.2); keep the citations so the card can attribute every claim.

**Coding & agentic capability (4.8 vs 4.7):**

| Benchmark | 4.8 | 4.7 | Note (System Card §) |
| --- | --- | --- | --- |
| SWE-bench Verified | 88.6 | 87.6 | near-saturated (§8.2) |
| SWE-bench Pro | **69.2** | 64.3 | biggest real coding delta; GPT-5.5 58.6 (§8.2) |
| SWE-bench Multilingual | 84.4 | 80.5 | §8.2 |
| SWE-bench Multimodal | 38.4 | 34.5 | visual SWE still hard (§8.2) |
| Terminal-Bench 2.1 | 74.6 | 66.1 | **GPT-5.5 leads at 78.2**; latency-sensitive; Opus run at *high* (§8.3) |
| GraphWalks BFS @1M | **68.1** | 40.3 | long-context jump (§8.9) |
| GraphWalks Parents @1M | 83.3 | 56.6 | §8.9 |
| BrowseComp | 84.3 / 88.5 multi | 79.8 | §8.1 |
| GPQA Diamond | 93.6 | **94.2** | slight regression; Gemini 94.3 (§8.6) |
| USAMO 2026 | 96.7 | 69.3 | math leap, uncontaminated (§8.7) |

**Effort — the headline (System Card Fig 8.2.A):** on SWE-bench Pro the pass rate **peaks at `xhigh`,
with `max` comparable**, and **at minimum effort Opus 4.8 matches the peak of Opus 4.7 at maximum
effort.** Translation for the card: upgrading frequently means *same quality, lower effort, less
cost/latency* — not "pay more for more."

**Honesty & diligence (§6.3.6 — note: toy, short-context evals):**

- *Uncritically reporting flawed results* — Opus 4.8 is the **first model with a perfect score**
  (never reports false numbers); §6.1.2 calls it the first model at a 0% bad-behavior rate.
- *Code-summary honesty* — fails to flag failures only **3.7%** of the time (5× better than Mythos
  Preview's 27.6%); large drop from 4.7.
- *Lazy investigation* — **first Claude to score perfectly**; 4.7 was wrong 25% of the time.
- *Overconfidence* — **> 10× better than 4.7** (admits it doesn't know; validates a teammate's
  subtly-wrong example).
- Announcement framing: *"~4× less likely than its predecessor to allow flaws in code it has
  written to pass unremarked."*

**The caveats the card must carry (this is what makes it honest, not hype):**

- The §6.3.6 wins are measured on *"relatively simple 'toy'… short-context"* evals the card itself
  flags as *"not as predictive of the long-context scenarios where Claude is most likely to exhibit
  these failure modes."* This reconciles with the field reports of sloppy long-horizon runs → the
  honesty win lands in **short, verify-gated loops** (exactly what rung 3 measures).
- §6.1.2's most-concerning trend: a growing tendency toward **grader speculation** that *"may
  suggest Opus 4.8 prioritizes the appearance of task success over actual task success"* (did not
  translate to worse outward behavior, but name it for unattended/agentic use).
- Not a clean sweep: **Terminal-Bench** still goes to GPT-5.5; **GPQA dipped**; field reports note
  third-party proxies/aggregators lagged on 4.8 (you may be served 4.7 silently).

**Effort mechanics (Claude Code `model-config` docs — needed by §5):**

- Levels for Opus 4.8: `low / medium / high (default) / xhigh / max`. (Opus 4.7 default is `xhigh`.)
- Set via: `--effort <level>` flag (session); `effortLevel` in settings (**`low`–`xhigh` only** —
  `max`/`ultracode` not accepted there); `CLAUDE_CODE_EFFORT_LEVEL` env (**highest precedence**;
  the one place `max` persists). `ultracode` = `"ultracode": true` via `--settings` — *not* an
  effort level; it sends `xhigh` **plus** dynamic-workflow orchestration.
- Requires Claude Code ≥ v2.1.154. Unsupported levels degrade gracefully (Claude Code falls back to
  the highest supported level ≤ requested).

## 4. Rung 1 — the adoption card

### 4.1 Invocation

`/header opus-4.8` (the topic-arg slot already accepts a name/UUID/URL; `opus-4.8` and any future
`<model>` route to the adoption render mode). Also reachable organically via the in-repo
`MODEL-UPGRADE` finding (§6). Runs with **no repo and no API key**.

### 4.2 Composition — snapshot ⊕ local audit

The bundled snapshot is **briefing-shaped JSON** (same schema as a fetched briefing: `summary`,
`key_developments`, `source_articles`) plus a `decision` block (`verdict_by_engine`, `rubric`,
`watch_outs`, `effort_note`). Reusing the briefing schema means the card flows through the **same
render path** as a live briefing — a future live adoption topic (§2 fast-follow) is then a drop-in
content swap, no new client code. Proposed path: `header/data/engine-adoption/opus-4.8.json`,
seeded from §3 with citations.

The card = snapshot (grounded population evidence) **⊕** local audit (personalization):

- current model + effort — settings precedence `CLAUDE_CODE_EFFORT_LEVEL` → `effortLevel` →
  model default;
- realized spend / share by model — `header-cost report --json` over `~/.claude` (installation-
  scoped, so it works with no repo).

### 4.3 Personalized verdict by detected engine

| Detected engine | Lead with |
| --- | --- |
| `opus-4-7 @xhigh` (+ meaningful spend) | **effort-drop savings** — "4.8 @high likely holds your quality at less cost; prove it" |
| `sonnet` / older | **capability gain** — Pro 69.2, long-context, honesty |
| already `opus-4-8` | **reverse optimization** — "can you *drop* effort and save?" (the move nobody else offers) |

### 4.4 Card layout (illustrative)

```
Opus 4.8 — adopt in your harness?            [System Card · May 28 2026]
────────────────────────────────────────────────────────────────────────
You: opus-4-7 @xhigh · ~$X/wk on opus-4-7 (NN% of spend)   [from ~/.claude]

VERDICT  Switch for coding — but tune effort, don't just flip the model.
         Min-effort 4.8 ≈ max-effort 4.7 on SWE-bench Pro.

WHY      SWE-bench Pro 69.2 vs 64.3 · same $5/$25 · code-honesty misleads
         3.7% (4.7 much higher) · long-context BFS@1M 68.1 vs 40.3
WATCH    toy-eval honesty ≠ long unattended runs (card says so) ·
         grader-speculation trend · Terminal-Bench: GPT-5.5 ahead ·
         proxies may still serve you 4.7

NEXT  ▸ prove it on your code →  cd <repo> && header experiment opus-4.8
```

## 5. Rung 3 — the engine-swap experiment

### 5.1 Arm schema + `--effort` plumbing

Extend the arm row from `label | model | overrides_dir` to **`label | model | effort | overrides_dir`**
(new optional `effort:` key; existing specs without it are unchanged). In `run_one`
(`header-experiment` ~:1512) the model is applied as a `--model` flag; effort is the symmetric
addition:

```sh
[ -n "$model" ]  && extra_args+=(--model  "$model")    # existing (:1512)
[ -n "$effort" ] && extra_args+=(--effort "$effort")   # new
```

`--effort max` is fine headless (each `claude --print` is a fresh session). Use the flag, not a
worktree `settings.json` write — `effortLevel` can't hold `max`/`ultracode`, and the flag keeps the
arm a pure engine swap rather than tripping the overrides → `harness-change` classifier.

### 5.2 Pin the control (correctness wrinkle)

Arm A ("current") **must not be ambient**. Effort precedence means an unpinned control inherits
whatever floats in the environment. Detect the user's actual effort (`CLAUDE_CODE_EFFORT_LEVEL` →
`effortLevel` setting → model default) and pass it explicitly as arm A's `effort`, so the control is
reproducible and the verdict reads against the engine the user *actually* runs (usually
`4.7 @xhigh`, **not** `@max`).

### 5.3 New `engine-swap` kind

`detect_kind` (`header-experiment` ~:2485) currently keys on distinct model count (≥2 →
`model-swap`). Two arms sharing a model but differing on effort (`4.8 @high` vs `4.8 @xhigh`) would
slip to `generic`. Add **`engine-swap`** = arms differ on model **and/or** effort. Thread `effort`
into the sync arm objects and the `report` scorecard (show the effort dimension).

### 5.4 `merge` — persistable wins write settings

Today a `model-swap` merge is advisory (`~:2346`, "update your default — header-config doesn't
manage model"). Upgrade for `engine-swap`: when the winning arm's level is **persistable**
(`low`–`xhigh`), `merge` offers to write `model` + `effortLevel` into `settings.json` (still shows
the diff, still asks). When the win is on `max`/`ultracode` (not settings-persistable), stay
advisory and print the exact `/effort` / env-var instruction.

### 5.5 The `opus-4.8` scaffolder

`header experiment opus-4.8` (thin wrapper over `mine` + `new --kind engine-swap`) pre-fills:

- **Arm A** = detected current model @ detected current effort (the pinned control, §5.2)
- **Arm B** = `claude-opus-4-8` @ `high`
- **Arm C** = `claude-opus-4-8` @ `xhigh`
- **Tasks** = `mine`d from the repo's FAIL_TO_PASS history (the keystone), tests-oracle verify
- **Hypothesis** = "Opus 4.8 is non-inferior on success and cheaper-or-better than `<current>` on
  this repo's own historical fixes — at the lowest effort that holds quality."
- **`audit_basis`** = the adoption snapshot id (provenance for the sync payload / ledger)

Generalize the name: `header experiment <model>` for future releases.

### 5.6 Optional — `ultracode` arm (fast-follow)

A 4th arm `D = opus-4-8 ultracode` (via `--settings '{"ultracode":true}'`, = `xhigh` + dynamic
workflows) puts a price tag on the behavior behind the field complaints about token-burn /
"spins up agents at the drop of a hat." Higher cost + variance → opt-in (`--ultracode`), not
default.

## 6. In-repo surfacing — `MODEL-UPGRADE`

Add a `header-audit` line **`MODEL-UPGRADE <current> <recommended>`** — an *opportunity*, distinct
from `MODEL-STALE` *debt* (4.7 → 4.8 isn't stale). Fires when the snapshot/briefing names a newer
recommended engine than the detected model. Carries the `[Experiment]` disposition and links to
`header experiment opus-4.8`, so the card reaches users two ways: explicit `/header opus-4.8`, and
inside any normal audit. Conservative like `MODEL-STALE`: only fires on a named, shipped successor.

## 7. Sync & privacy

`engine-swap` rides the existing sync (`POST /api/v2/experiments`) unchanged (§2). New data on the
wire is only the arm `effort` (a label) and `kind:"engine-swap"` — no new sensitive fields; the
privacy contract (override paths not contents, task titles not bodies, no logs) is unchanged.
`audit_basis` points at the adoption snapshot rather than a server briefing id when the snapshot
backs the card.

## 8. Launch cut vs fast-follows

**v0.18.0 (the launch cut, all client-side):**
1. Bundled snapshot `header/data/engine-adoption/opus-4.8.json` (§3, §4.2).
2. Card render mode + `/header opus-4.8` routing + personalized verdict (§4).
3. `engine-swap`: arm `effort`, `--effort` plumbing, control-pinning, `detect_kind`, report,
   sync arm field (§5.1–5.3).
4. `merge` writes `model`+`effortLevel` for persistable wins (§5.4).
5. `header experiment opus-4.8` scaffolder (§5.5).
6. `MODEL-UPGRADE` audit line (§6).

**Fast-follows (don't block launch):** `ultracode` arm (§5.6); live adoption briefing + dashboard
effort column (§2, backend); wire to the schedule integration already on the
[experiments roadmap](../ROADMAP.md) ("new Opus dropped → queue a migration experiment").

## 9. Testing

Match existing suites (`header/test/audit.test.sh`, `experiment.test.sh`, `cost.test.sh`):

- **engine-swap:** `--effort` reaches the adapter (assert via `HEADER_EXPERIMENT_ADAPTER` stub
  capturing argv); control effort is detected + pinned; `detect_kind` returns `engine-swap` for
  same-model/diff-effort and for diff-model arms; sync payload carries `effort` + `engine-swap`.
- **merge:** persistable win writes `model`+`effortLevel` to `settings.json`; `max` win stays
  advisory.
- **scaffolder:** `header experiment opus-4.8` emits A=detected / B=4.8@high / C=4.8@xhigh with a
  mined task and the hypothesis/audit_basis filled.
- **audit:** `MODEL-UPGRADE` fires only with a named successor in the snapshot; does not fire when
  already on the recommended engine.
- **card:** render mode composes snapshot ⊕ local audit; verdict branch matches detected engine;
  runs with no repo and no key.

## 10. References

- **System Card: Claude Opus 4.8** (May 28 2026) — primary source. Key §: 8.1–8.9 (capabilities),
  Fig 8.2.A (effort curve), 6.1.2 (alignment key findings), 6.3.6 (diligence & honesty),
  6.3.1 (overeager GUI), 8.11.3 (multi-agent harnesses).
- Anthropic, *Introducing Claude Opus 4.8* — pricing, effort guidance, dynamic workflows.
- Claude Code docs, *Model configuration* — effort levels, `--effort`, `effortLevel`,
  `CLAUDE_CODE_EFFORT_LEVEL`, `ultracode`.
- Field commentary (effort-as-lever, default-effort "laziness," long-run reliability, proxy lag) —
  corroborates the §3 caveats; the card cites the System Card, not blog posts.
- Related: [experiments-design.md](experiments-design.md) (the proof engine),
  [experiments-sync-api.md](experiments-sync-api.md) (the unchanged sync contract).
