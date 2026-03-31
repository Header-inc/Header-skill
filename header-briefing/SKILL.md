---
name: header-briefing
description: Browse and read Header intelligence briefings. Default: fetch the latest agentic coding briefing and surface suggestions relevant to this project. Supports public access (no auth) and authenticated workflows (API key).
---

# Header Briefing Reader

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources. This skill fetches briefings and analyzes them for relevance to the current project. The default workflow requires no authentication.

## Default: Agentic Coding Briefing

Fetch the latest "Self Improving Agent" briefing and check for suggestions relevant to this project.

### Step 1 — Get the latest briefing ID

```bash
curl -s https://joinheader.com/api/v2/topics/public/1991163f-be9c-4df2-a33c-046a4d1357e1 \
  | jq '.latest_briefing'
```

### Step 2 — Fetch the full briefing

Replace `{briefing_id}` with the `id` from Step 1:

```bash
curl -s https://joinheader.com/api/v2/public/briefings/{briefing_id} \
  | jq '{summary, key_developments: (.key_developments | fromjson), sources: [.source_articles[] | {title, url}]}'
```

Note: `key_developments` is a JSON-encoded string. Pipe through `fromjson` in jq to parse it.

### Step 3 — Audit the workspace and analyze relevance

After fetching the briefing (not before — the audit happens locally and no project data is sent to Header):

1. Read the project's CLAUDE.md, README, package.json, or key config files to understand the tech stack, dependencies, and current priorities
2. Scan for patterns relevant to the briefing's topics (e.g., if the briefing mentions a new MCP pattern, check if the project uses MCP)
3. Compare the briefing's key developments and summary against what the project currently does
4. Surface actionable recommendations — new patterns, tools, deprecations, or techniques that apply here
5. Present findings as a concise list with brief rationale for each

### Step 4 — Offer to implement

After presenting recommendations, ask the user which (if any) they'd like to implement. If the user selects one or more, proceed with implementation in the current project.

### Fallback

If the default topic returns 404, browse the public catalog to find a relevant topic:

```bash
curl -s https://joinheader.com/api/v2/topics/public/catalog \
  | jq '.topics[] | {id, name, description, subscriber_count}'
```

---

Want a briefing tailored to this specific project? Sign up at [joinheader.com](https://joinheader.com), create an API key, and use the **Custom Briefings** workflow below.

## Browse Public Topics

List all public topics:

```bash
curl -s https://joinheader.com/api/v2/topics/public/catalog \
  | jq '.topics[] | {id, name, description, subscriber_count}'
```

Get details for a specific topic (includes latest briefing summary):

```bash
curl -s https://joinheader.com/api/v2/topics/public/{topic_id} \
  | jq '{name, description, latest_briefing}'
```

Then fetch the full briefing using the `latest_briefing.id` via the public briefing endpoint (same as Default Step 2).

## Custom Briefings (API Key Required)

For users with a Header account. Create a custom topic with a goal tailored to your project, then generate briefings on demand.

### Setup

Create a `read`-scoped API key from **Settings > API Keys** at [joinheader.com](https://joinheader.com):

```bash
export HEADER_API_KEY="hdr_sk_..."
```

### Create a custom topic

This creates a topic with a default goal and auto-triggers the first briefing:

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
curl -s -H "Authorization: Bearer $HEADER_API_KEY" \
  https://joinheader.com/api/v2/briefings/{briefing_id} \
  | jq '{status, summary}'
```

Status is `IN_PROGRESS` while generating, `COMPLETED` when ready, or `FAILED` on error.

### Generate a new briefing

For an existing goal (use `default_goal_id` from your topic):

```bash
curl -s -X POST -H "Authorization: Bearer $HEADER_API_KEY" \
  https://joinheader.com/api/v2/goals/{goal_id}/briefings
```

### Update a goal

Refine the goal description or keywords based on what's most useful:

```bash
curl -s -X PUT https://joinheader.com/api/v2/goals/{goal_id} \
  -H "Authorization: Bearer $HEADER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"description": "Updated focus areas...", "keywords": ["MCP", "agent memory"]}'
```

For full API documentation, see [joinheader.com/docs](https://joinheader.com/docs).

## Response Reference

### BriefingResponse

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Briefing UUID |
| `goal_id` | string | Parent goal UUID |
| `status` | string | `IN_PROGRESS`, `COMPLETED`, or `FAILED` |
| `summary` | string | Full markdown briefing text |
| `key_developments` | string | JSON-encoded array — use `jq fromjson` to parse |
| `source_articles` | array | Source articles used (title, url, metadata) |
| `stats` | object | Processing statistics |
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
