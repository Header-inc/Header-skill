# Header reference — custom briefings

*Loaded on demand by the Header skill; not part of the always-loaded SKILL.md.*

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

**Team-relevant settings only.** Because the file is committed, only the allow-list is honored: `default_topic`, `staleness_days`, `schedule_frequency_days`, `language`. Personal preferences and **anything consent-, code-, or egress-related** (`telemetry`, `auto_update`, `auto_tune`, `update_check`, `experiment_sync`, `aggregate_submit`) are **ignored** by design — `header-config team-show` makes its effective contents auditable.

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

### Sync an experiment (`POST /api/v2/experiments`)

Account-scoped, idempotent **upsert** keyed by `client_key` (`<installation_id>:<experiment_id>`) so re-syncing the same experiment as it progresses (defined → run → analyzed → merged) updates one record. Driven automatically by `header-experiment` on each lifecycle change when a key is present (and by manual `push`); this is the underlying contract. **Metadata only — never code, prompt bodies, override contents, or logs.**

```bash
curl -sS -w "\n%{http_code}" -X POST https://joinheader.com/api/v2/experiments \
  -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  -d @- <<'JSON'
{
  "v": 1,
  "client_key": "<installation_id>:<experiment_id>",
  "skill_version": "0.14.0",
  "submitted_at": "2026-05-28T18:22:45Z",
  "experiment": {
    "id": "slim-claude-md-20260527-141627",
    "kind": "harness-change",            // harness-change | model-swap | generic
    "description": "Slim CLAUDE.md: compress 4 skill-redundant sections…",
    "status": "analyzed",                // defined | run | analyzed
    "replicates": 3,
    "non_inferiority_margin": 0.02,
    "commit_ref": "HEAD",
    "arms": [
      {"label":"A","model":"","role":"control","overrides":null},
      {"label":"B","model":"","role":"treatment","overrides":"arms/B"}
    ],
    "tasks": [
      {"id":"t1","title":"Add a briefing_count field to the v2 Goal model",
       "title_source":"derived","verify":"pytest tests/v2/ -x -q",
       "prompt_ref":"tasks/t1.md","prompt_sha256":"b2938df7…","prompt_bytes":308}
    ]
  },
  "hypothesis": {                        // present whenever a statement exists (it almost always does)
    "statement":"Slimming CLAUDE.md keeps success non-inferior at materially lower per-turn token cost",
                                          //   ↑ the full claim in words — the dashboard headline. The
                                          //     spec's `hypothesis:` field, falling back to `description`.
    "ledger_key":"slim-claude-md",       // ↓ provenance — blank unless the experiment traces to a finding
    "title":"Slim CLAUDE.md — 644 lines / ~9,739 tokens loaded every turn",
    "source_url":"https://www.youtube.com/watch?v=…",
    "disposition":"wanted"
  },
  "audit_basis": {"topic_id":"1991163f-…","goal_id":"","briefing_id":"3c9b6bbd-…"},
  "repo":    {"key":"github.com/me/repo","name":"repo","branch":"main","commit":"5214a29"},
  "machine": {"installation_id":"<uuid>","hostname":"…","os":"linux","arch":"x86_64"},
  "result":  { /* result.json verbatim: verdict, cost/success CIs, per_task — or null */ }
}
JSON
```

Expected success response (`200`/`201`): `{"id":"<server_id>","client_key":"…","url":"https://joinheader.com/experiments/<server_id>","status":"stored"}`. Surface the `url`. `goal_id` may be empty — the server can resolve the goal from `briefing_id` (a briefing belongs to a goal), or the client supplies it via `--goal`. Free-tier callers may get `EXPERIMENT_SYNC_FREE` (Pro-only) — run the trial/upgrade flow.

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

### ExperimentSyncResponse (`POST /api/v2/experiments`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Server-assigned experiment record id |
| `client_key` | string | Echoes the request's idempotency key (`<installation_id>:<experiment_id>`) |
| `url` | string | Web UI link to the synced experiment — surface this to the user |
| `status` | string | `stored` (created or updated) |

The request body is the `header-experiment push` payload documented under "Sync an experiment (`POST /api/v2/experiments`)". The receiving endpoint is **live** (it upserts on `client_key` and returns the web-UI `url` — surface it). A `404`/`405` from it now indicates a stale deployment or a proxy in the way, not a missing handler; the client's retry-on-next-edit behavior still applies.

