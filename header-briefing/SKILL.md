---
name: header-briefing
description: Browse and read Header intelligence briefings. Default: fetch the latest agentic coding briefing and surface suggestions relevant to this project. Supports public access (no auth) and authenticated workflows (API key).
when_to_use: Use when the user asks what's new in agents/MCP/coding tools, any new patterns to adopt, or invokes /header-briefing. Pass a topic name or UUID as the argument to fetch a specific topic; otherwise the default agentic-coding briefing is used.
argument-hint: "[topic-name-or-uuid]"
allowed-tools: Bash
---

*The `when_to_use`, `argument-hint`, and `allowed-tools` frontmatter fields are honored by Claude Code; other harnesses ignore them safely.*

# Header Briefing Reader

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources. This skill fetches briefings and analyzes them for relevance to the current project. The default workflow requires no authentication.

> This skill uses `curl` so it runs in any agent with shell access (Claude Code, Cursor, Aider, OpenAI Codex CLI, Goose, etc.). Claude Code users may substitute `WebFetch` for the read-only GETs if they prefer.

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

### Step 0 — Resolve the topic

Determine the topic UUID using this fallback chain (first match wins):

1. **Explicit argument** — if the user passed a topic identifier:
   - UUID format → use directly as the topic ID.
   - Anything else → search `/api/v2/topics/public/catalog` for a case-insensitive substring match on `name`. If exactly one matches, use its `id`. If multiple match, ask the user to disambiguate. If none match, fall through.
2. **`HEADER_DEFAULT_TOPIC`** env var → use as the topic ID.
3. **Hardcoded default** → `1991163f-be9c-4df2-a33c-046a4d1357e1` (Self Improving Agent).

**Claude Code only:** the explicit argument is delivered as `$ARGUMENTS` when invoked via `/header-briefing <topic>`. Other harnesses: extract the topic identifier from the user's message text.

### Step 1 — Get the latest briefing ID

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

1. **Identify the project's stack and tooling** from whatever metadata the project happens to use — package manifests, lockfiles, language version files, build/test/CI configs, container or infrastructure definitions, agent/skill definitions. Read `CLAUDE.md` and the project README if present for stated context and conventions.

2. **Find what the team already knows is broken, missing, or pending.** Look for learnings, post-mortems, runbooks, retrospectives, architecture/decision records, changelogs, roadmaps, backlogs/TODO docs, and incident reports — at the repo root and in any conventional documentation directory. Also do a quick scan for in-code `TODO`/`FIXME`/`HACK` markers as a density signal. Cite source files when you reference an item.

3. **Build the audit summary.** This is the structured input to Step 4 — its job is to make the comparison between the briefing's content and the project's actual state explicit, so recommendations are grounded in observed reality rather than generic best-practice. Populate each row with items relevant to the briefing topic, not an exhaustive inventory:

   - **Stack** — languages, frameworks, runtime versions. The topic-relevance filter: items here scope which parts of the briefing apply at all (a React pattern doesn't help a Go shop).
   - **Tooling** — package manager, build/test/CI tooling, agent-related deps (MCP servers, AI SDKs, etc.). The layer where briefings about new tools, runners, and workflows usually land.
   - **Known issues / pain points** — themes drawn from step 2; group similar items and cite the source file. The highest-leverage row: a briefing item that addresses a named pain point jumps the queue in step 4.
   - **Mentioned in briefing** — items from the briefing's `key_developments` or `summary` that overlap anything in Stack, Tooling, or Known issues. The first-pass relevance filter.
   - **Gaps** — patterns the briefing endorses that this project doesn't yet use, including cases where the project's current approach is now considered legacy or superseded.

4. **Surface recommendations** drawn from **Mentioned in briefing**, **Gaps**, and especially anything that addresses an entry in **Known issues / pain points**. Prioritize the last group — the team has already named these as problems, so a briefing-backed remediation is more actionable than a greenfield suggestion. Each recommendation gets one sentence of rationale tying it to a specific item from the audit, citing the source file when it maps to a known issue.

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

### Fallback

If the default topic returns 404, browse the public catalog to find a relevant topic:

```bash
curl -sS -w "\n%{http_code}" https://joinheader.com/api/v2/topics/public/catalog
```

Pick a topic from the returned list (each entry has `id`, `name`, `description`, `subscriber_count`) and use its `id` in place of the default topic ID above.

---

Want a briefing tailored to this specific project? Sign up at [joinheader.com](https://joinheader.com), create an API key, and use the **Custom Briefings** workflow below.

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

### Setup

Create a `read`-scoped API key from **Settings > API Keys** at [joinheader.com](https://joinheader.com):

```bash
export HEADER_API_KEY="hdr_sk_..."
```

### Create a custom topic

POST to the Header API to create a topic with a default goal and auto-trigger the first briefing:

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

### Scheduled / agent loop

For agents running on a cron or scheduled trigger (e.g., a daily check-in), use `GET /api/v2/topics/dashboard` with `?since=<iso8601>` to get only topics whose latest briefing changed after the timestamp. The response includes a server-computed `next_action` enum so the agent knows whether to surface a new briefing without re-deriving it client-side.

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
