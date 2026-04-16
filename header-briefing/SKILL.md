---
name: header-briefing
description: Browse and read Header intelligence briefings. Default: fetch the latest agentic coding briefing and surface suggestions relevant to this project. Supports public access (no auth) and authenticated workflows (API key).
allowed-tools: WebFetch
---

# Header Briefing Reader

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources. This skill fetches briefings and analyzes them for relevance to the current project. The default workflow requires no authentication.

## Default: Agentic Coding Briefing

Fetch the latest "Self Improving Agent" briefing and check for suggestions relevant to this project.

### Step 1 — Get the latest briefing ID

Use the WebFetch tool:

- **URL**: `https://joinheader.com/api/v2/topics/public/1991163f-be9c-4df2-a33c-046a4d1357e1`
- **Prompt**: `Return the JSON object. I need the latest_briefing.id value.`

Extract the `latest_briefing.id` from the response — this is the briefing ID for Step 2.

### Step 2 — Fetch the full briefing

Use the WebFetch tool with the briefing ID from Step 1:

- **URL**: `https://joinheader.com/api/v2/public/briefings/{briefing_id}`
- **Prompt**: `Return the full JSON response. I need: summary, key_developments, source_articles (title and url for each), and generated_at.`

Note: `key_developments` is a JSON-encoded string — parse it from the string into a structured list.

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

- **URL**: `https://joinheader.com/api/v2/topics/public/catalog`
- **Prompt**: `Return all topics with their id, name, description, and subscriber_count.`

---

Want a briefing tailored to this specific project? Sign up at [joinheader.com](https://joinheader.com), create an API key, and use the **Custom Briefings** workflow below.

## Browse Public Topics

List all public topics using WebFetch:

- **URL**: `https://joinheader.com/api/v2/topics/public/catalog`
- **Prompt**: `Return all topics with their id, name, description, and subscriber_count.`

Get details for a specific topic (includes latest briefing summary):

- **URL**: `https://joinheader.com/api/v2/topics/public/{topic_id}`
- **Prompt**: `Return the topic name, description, and latest_briefing details.`

Then fetch the full briefing using the `latest_briefing.id` via the public briefing endpoint (same as Default Step 2).

## Custom Briefings (API Key Required)

For users with a Header account. Create a custom topic with a goal tailored to your project, then generate briefings on demand.

### Setup

Create a `read`-scoped API key from **Settings > API Keys** at [joinheader.com](https://joinheader.com):

```bash
export HEADER_API_KEY="hdr_sk_..."
```

### Create a custom topic

Use the Bash tool to POST to the Header API. This creates a topic with a default goal and auto-triggers the first briefing:

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

Use the WebFetch tool:

- **URL**: `https://joinheader.com/api/v2/briefings/{briefing_id}`
- **Prompt**: `Return the status and summary fields from this JSON response.`

Note: this endpoint requires the `Authorization: Bearer $HEADER_API_KEY` header for private briefings. If WebFetch cannot set headers, use Bash with curl instead:

```bash
curl -s -H "Authorization: Bearer $HEADER_API_KEY" \
  https://joinheader.com/api/v2/briefings/{briefing_id}
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
| `key_developments` | string | JSON-encoded array — parse from string into structured list |
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
