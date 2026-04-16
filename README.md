# Header Briefing Skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that fetches intelligence briefings from [Header](https://joinheader.com) and surfaces recommendations relevant to your current project.

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources covering AI agent frameworks, MCP, coding tools, and related topics.

## Installation

### Option 1: Global (available in all projects)

```bash
git clone https://github.com/Header-inc/Header-skill.git
mkdir -p ~/.claude/skills/header-briefing
cp Header-skill/header-briefing/SKILL.md ~/.claude/skills/header-briefing/SKILL.md
```

### Option 2: Project-local (available only in one project)

```bash
git clone https://github.com/Header-inc/Header-skill.git
mkdir -p .claude/skills/header-briefing
cp Header-skill/header-briefing/SKILL.md .claude/skills/header-briefing/SKILL.md
```

Start a new Claude Code session (or restart your current one) to pick up the skill.

## Usage

### Default: Agentic Coding Briefing (No Auth Required)

Simply invoke the skill:

```
/header-briefing
```

This will:

1. Fetch the latest "Self Improving Agent" briefing from Header's public API
2. Read your project's config files (CLAUDE.md, README, package.json, etc.) to understand your tech stack
3. Compare the briefing's key developments against your project's patterns and dependencies
4. Present actionable recommendations with rationale
5. Offer to implement any recommendations you select

Your project data never leaves your machine — the workspace audit happens locally after the briefing is fetched.

### Browse Public Topics

You can also ask the skill to browse Header's public topic catalog instead of using the default topic. Public topics span a variety of technology areas and each has its own curated source list and briefing history.

Ask Claude to list available topics or fetch a briefing from a specific topic by name or ID.

### Custom Briefings (API Key Required)

For briefings tailored to your specific project and tech stack:

1. Sign up at [joinheader.com](https://joinheader.com)
2. Create a `read`-scoped API key from **Settings > API Keys**
3. Export it as an environment variable:

```bash
export HEADER_API_KEY="hdr_sk_..."
```

With an API key, you can:

- **Create custom topics** with goal descriptions tailored to your project
- **Generate briefings on demand** for any of your topics
- **Update goals** to refine focus areas and keywords over time
- **Check briefing status** for async generation (`IN_PROGRESS`, `COMPLETED`, `FAILED`)

## Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `HEADER_API_KEY` | No | Header API key (`hdr_sk_...`) for authenticated workflows. Only needed for custom topics and on-demand briefing generation. |

## License

MIT — see [LICENSE](LICENSE) for details.
