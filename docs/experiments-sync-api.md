# Experiment Sync API — backend contract

What the Header **skill** sends so a user's experiments show up on their dashboard.
This is the contract for the receiving endpoint, which is **not built yet**
(`POST /api/v2/experiments` currently returns `405`). The client side ships in skill
v0.14.0 and makes the call on every experiment lifecycle change. Build the handler to
match this shape.

> Nothing executes server-side. This is a **record/display** sync: store it, show it
> in the UI. No experiments run on Header infra.

---

## Endpoint

```
POST /api/v2/experiments
Authorization: Bearer hdr_sk_...        # the user's API key → resolves the account
Content-Type: application/json
```

- **Auth required.** Resolve the owning account from the API key. No key → the client
  never calls this (so a missing-auth path is just a normal `401`).
- **Idempotent UPSERT keyed by `client_key`** (`<installation_id>:<experiment_id>`).
  The same experiment is sent repeatedly as it progresses (`defined → run → analyzed →
  merged`) and on every edit — each call **updates the same record**, never creates a
  duplicate. Expect **many small writes per experiment**; make the write cheap and
  idempotent. Last-write-wins on `submitted_at` is fine.
- **Frequency:** one call per lifecycle command per experiment (`new`, `define`,
  `validate`, `run`, `analyze`, `merge`). Low volume per user, but bursty.

---

## Request body

Top level:

| Field | Type | Notes |
|---|---|---|
| `v` | int | Payload schema version (currently `1`). Version your parser on this. |
| `client_key` | string | **Idempotency key.** `<installation_id>:<experiment_id>`. Stable across re-syncs of the same experiment from the same machine. |
| `skill_version` | string | Header skill version that produced the payload (e.g. `0.14.0`). |
| `submitted_at` | string (ISO-8601 UTC) | When the client sent it. Use for last-write-wins / "last synced". |
| `experiment` | object | See below. Always present. |
| `hypothesis` | object \| null | The audit finding this experiment tests. `null` when the experiment isn't tied to a finding. |
| `audit_basis` | object | Which topic/goal/briefing the hypothesis came from. Fields may be empty strings. |
| `repo` | object | The repository the experiment targets. |
| `machine` | object | The machine that ran it. |
| `result` | object \| null | The analysis output. `null` until the experiment has been `analyze`d. See "result object". |

### `experiment`

| Field | Type | Notes |
|---|---|---|
| `id` | string | Client-local experiment id (unique per machine; globally unique with `installation_id`). |
| `kind` | string enum | `harness-change` \| `model-swap` \| `generic`. (May carry other values if a future client sets a precise kind — treat as a label.) |
| `description` | string | Human title of the experiment. Safe to display. |
| `status` | string enum | `defined` \| `run` \| `analyzed` \| `merged`. **This is the "last status" the UI tracks.** Monotonic in normal use but don't assume it — trust each upsert. |
| `replicates` | int \| null | Replicates per (task, arm). |
| `non_inferiority_margin` | float \| null | δ for the success-rate non-inferiority gate. |
| `commit_ref` | string | The pinned git ref (e.g. `HEAD`). |
| `arms` | array<object> | The A/B (or A/A) arms. |
| `tasks` | array<object> | The tasks the agent runs. |

**`experiment.arms[]`**

| Field | Type | Notes |
|---|---|---|
| `label` | string | `A`, `B`, … |
| `model` | string | Model id; may be empty string (e.g. prompt-debt experiments don't change the model). |
| `role` | string enum | `control` (label `A`) \| `treatment`. |
| `overrides` | string \| null | Relative **path** to the arm's override dir (e.g. `arms/B`), or `null`. **Path only — never file contents.** |

**`experiment.tasks[]`**

| Field | Type | Notes |
|---|---|---|
| `id` | string | Task id (`t1`, …). |
| `title` | string | Human label for the task. Safe to display. |
| `title_source` | string enum | `authored` (user wrote it; trustworthy) \| `derived` (summarized from the prompt's first heading — descriptive, treat as approximate) \| `id` (fallback = the task id). |
| `verify` | string | The verifier command (e.g. `pytest -x -q`). |
| `prompt_ref` | string | Path/reference to the prompt file on the user's machine. **For identity only — do not expect to fetch it.** |
| `prompt_sha256` | string (hex) \| "" | Content hash of the prompt, for dedupe. Empty if unavailable. |
| `prompt_bytes` | int | Size of the prompt file. |

> **The prompt BODY is never sent.** Only title + sha256 + byte count. Same for override
> files (paths only) and agent logs (never sent). Don't design fields expecting them.

### `hypothesis` (object | null)

| Field | Type | Notes |
|---|---|---|
| `ledger_key` | string | Client-local stable key for the finding (e.g. `slim-claude-md`). **Not a server id** — treat as a per-user/per-repo label; good for grouping experiments that test the same finding. |
| `title` | string | The finding's title. May be empty if the ledger had no record. |
| `source_url` | string | The briefing source article that motivated it. May be empty. |
| `disposition` | string | Latest ledger action: `surfaced` \| `applied` \| `dismissed` \| `snoozed` \| `wanted` \| "". |

### `audit_basis`

| Field | Type | Notes |
|---|---|---|
| `topic_id` | string | Header topic UUID the audit was enriched from. May be empty. |
| `goal_id` | string | Goal UUID. **Often empty** — resolve it server-side from `briefing_id` (a briefing belongs to a goal), or accept the client-supplied value when present. |
| `briefing_id` | string | The briefing UUID that enriched the audit. May be empty. |

These are your **join keys** to existing topic/goal/briefing tables.

### `repo`

| Field | Type | Notes |
|---|---|---|
| `key` | string | **Stable repo identity** = normalized git remote (e.g. `github.com/org/repo`), clone-agnostic. Falls back to a local path if no remote. Group experiments by this. |
| `name` | string | Repo basename. |
| `branch` | string | Current branch. May be empty. |
| `commit` | string | Short SHA of `commit_ref`. May be empty. |

### `machine`

| Field | Type | Notes |
|---|---|---|
| `installation_id` | string (UUID) | Stable per-machine id. Group experiments by machine; also the left half of `client_key`. |
| `hostname` | string | Machine hostname. |
| `os` | string | `linux` / `darwin` / … |
| `arch` | string | `x86_64` / `arm64` / … |

### `result` object (when `status` ≥ `analyzed`; else `null`)

Emitted verbatim from the client's analysis. **`cost` is the billed/"win" metric;
`success` is the non-inferiority guardrail.**

| Field | Type | Notes |
|---|---|---|
| `mode` | string | `ab` (A vs B) \| `aa` (noise-floor self-check). |
| `arms` | [string, string] | The two arm labels compared. |
| `tasks_paired` | int | Number of paired tasks in the analysis. |
| `n_per_arm` | [int, int] | Clean runs per arm. |
| `excluded_runs` | int | Runs dropped (agent error/timeout). May be absent → treat as 0. |
| `analysis_method` | string | `paired-by-task` \| `replicate-level`. |
| `bootstrap_iters` | int | Bootstrap resamples. |
| `non_inferiority_margin` | float | δ used. |
| `cost` | object | `{A_mean, B_mean, diff_mean_BA, ci95:[lo,hi], favorable:bool}` — USD per task, paired means; `favorable` = cost CI upper bound < 0. |
| `success` | object | `{A_rate, B_rate, diff_BA, ci95:[lo,hi], non_inferior:bool}` — success rates. |
| `per_task` | array | `[{task, A_cost, B_cost, diff_cost, A_succ, B_succ}]`. |
| `verdict` | string | Free-text verdict, e.g. `B wins`, `A wins`, `no proven win`, `underpowered`, `data degenerate`, `A/A OK …`, `A/A BIASED …`. Display as-is; key off the `cost.favorable` + `success.non_inferior` booleans for logic. |
| `reason` | string | Optional caveat (e.g. "only 1 task pair(s)…"). May be absent. |

---

## Response

**Success — `200` (updated) or `201` (created):**

```json
{
  "id": "exp_srv_abc123",
  "client_key": "5ce8a25c-...:slim-claude-md-20260527-141627",
  "url": "https://joinheader.com/experiments/exp_srv_abc123",
  "status": "stored"
}
```

The client surfaces `url` to the user ("view it at …"). `id` is your server-side record id.

**Errors** (follow the existing skill error conventions):

| HTTP | Body `error.code` | When | Client behavior |
|---|---|---|---|
| `401` | — | Missing/invalid key | Reports "key rejected"; suggests `experiment_sync off`. |
| `403` | `EXPERIMENT_SYNC_FREE` | Dashboard sync is Pro-only and caller is on free tier. Include `can_start_trial: bool`. | Runs the trial/upgrade flow. |
| `429` | `EXPERIMENT_SYNC_QUOTA` | Paid tier at a cap. | Surfaces and backs off. |
| `400`/`422` | — | Malformed body | Surfaces; does not retry blindly. |
| `5xx` | — | Server error | Best-effort; retries on the next lifecycle edit. |

Sync is **best-effort on the client** — any non-2xx is logged locally (`.last-sync`
marker) and retried on the next edit. It never blocks the user's experiment. So a
brief outage or partial deploy is safe.

---

## Suggested data model

- **`experiments`** table: PK = server id; unique index on `(account_id, client_key)`
  for the upsert. Columns mirror the payload (or store `experiment` + `result` as JSONB
  and project the hot fields: `status`, `kind`, `repo_key`, `installation_id`,
  `topic_id`, `briefing_id`, `submitted_at`).
- **Joins:** `audit_basis.topic_id` / `goal_id` / `briefing_id` → existing tables.
  `repo.key` and `machine.installation_id` are good secondary group-bys for the UI
  ("experiments in this repo", "on this machine").
- `hypothesis.ledger_key` is a **client-local label**, not an FK — index it for grouping
  but don't assume it resolves to a server row.

## Read endpoints the UI will need (not called by the skill — for your dashboard)

These aren't part of the client contract, but the dashboard needs them:

```
GET /api/v2/experiments?repo=<key>&status=<s>&since=<iso>   # list for the account
GET /api/v2/experiments/{id}                                # one experiment + its result/history
```

Shape them however suits the UI; the write contract above is the fixed part.

---

## Ground-truth example (a real client payload, verbatim)

`status: analyzed`, tied to a finding, with a result. Note `goal_id` is empty here
(resolve from `briefing_id`), and `result` is embedded verbatim (its own indentation —
still valid JSON).

```json
{
  "v": 1,
  "client_key": "5ce8a25c-6d6d-4ce9-940f-364b43e78944:slim-claude-md-20260527-141627",
  "skill_version": "0.14.0",
  "submitted_at": "2026-05-28T21:44:36Z",
  "experiment": {
    "id": "slim-claude-md-20260527-141627",
    "kind": "harness-change",
    "description": "Slim CLAUDE.md: compress 4 skill-redundant sections into pointer paragraphs. 644 → 484 lines, ~2,200 token reduction per turn.",
    "status": "analyzed",
    "replicates": 3,
    "non_inferiority_margin": 0.02,
    "commit_ref": "HEAD",
    "arms": [
      {"label":"A","model":"","role":"control","overrides":null},
      {"label":"B","model":"","role":"treatment","overrides":"arms/B"}
    ],
    "tasks": [
      {"id":"t1","title":"Add a 'briefing_count' field to the v2 Goal model and expose it on GET /api/v2/goals/{id…","title_source":"derived","verify":"pytest tests/v2/ -x -q --tb=short","prompt_ref":"tasks/t1.md","prompt_sha256":"b2938df744349024dae64f2b7696626d522353f2ea92277e5e77179b21ee768a","prompt_bytes":308}
    ]
  },
  "hypothesis": {"ledger_key":"slim-claude-md","title":"Slim CLAUDE.md — 644 lines / ~9,739 tokens loaded every turn","source_url":"https://www.youtube.com/watch?v=PIdETjcXNIk","disposition":"surfaced"},
  "audit_basis": {"topic_id":"1991163f-be9c-4df2-a33c-046a4d1357e1","goal_id":"","briefing_id":"3c9b6bbd-b9e8-4dac-b06d-464272bc6800"},
  "repo": {"key":"github.com/org/synthesize-engine","name":"synthesize-engine","branch":"main","commit":"5214a29"},
  "machine": {"installation_id":"5ce8a25c-6d6d-4ce9-940f-364b43e78944","hostname":"dev-box","os":"linux","arch":"x86_64"},
  "result": {
    "mode":"ab","arms":["A","B"],"tasks_paired":1,"n_per_arm":[3,3],"bootstrap_iters":2000,
    "non_inferiority_margin":0.02,
    "cost":{"A_mean":3.346213,"B_mean":4.773920,"diff_mean_BA":1.427707,"ci95":[1.427707,1.427707],"favorable":false},
    "success":{"A_rate":1.0,"B_rate":1.0,"diff_BA":0.0,"ci95":[0.0,0.0],"non_inferior":true},
    "per_task":[{"task":"t1","A_cost":3.346213,"B_cost":4.773920,"diff_cost":1.427707,"A_succ":1.0,"B_succ":1.0}],
    "verdict":"underpowered","reason":"only 1 task pair(s) — need more before a decision"
  }
}
```

A freshly-`define`d experiment looks the same minus the analysis: `status:"defined"`,
`hypothesis` possibly `null`, and `result: null`.
