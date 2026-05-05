# Header Briefing Skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A skill for agentic coding tools that fetches intelligence briefings from [Header](https://joinheader.com) and surfaces recommendations relevant to your current project. Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but works in any agent with shell access (Cursor, Aider, OpenAI Codex CLI, Goose, and others) — the skill uses plain `curl` under the hood.

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources covering AI agent frameworks, MCP, coding tools, and related topics.

## Installation

### Option A: Quick install (global, one command)

```bash
mkdir -p ~/.claude/skills/header-briefing && curl -sL https://raw.githubusercontent.com/Header-inc/Header-skill/main/header-briefing/SKILL.md -o ~/.claude/skills/header-briefing/SKILL.md
```

### Option B: Clone the repo (global, easier to update)

This skill is in beta and under active development. Keeping a local clone makes it easy to pull updates:

```bash
git clone https://github.com/Header-inc/Header-skill.git ~/Header-skill
mkdir -p ~/.claude/skills/header-briefing
cp ~/Header-skill/header-briefing/SKILL.md ~/.claude/skills/header-briefing/SKILL.md
```

To update later:

```bash
cd ~/Header-skill && git pull
cp header-briefing/SKILL.md ~/.claude/skills/header-briefing/SKILL.md
```

### Option C: Project-local (available only in one project)

```bash
git clone https://github.com/Header-inc/Header-skill.git
mkdir -p .claude/skills/header-briefing
cp Header-skill/header-briefing/SKILL.md .claude/skills/header-briefing/SKILL.md
```

Start a new Claude Code session (or restart your current one) to pick up the skill.

> **Note:** If you install both globally and in a project, the global version takes precedence and the project-local copy is silently ignored. Pick one method per skill name.

### Using with other harnesses (Cursor, Aider, Codex CLI, etc.)

The skill lives in a single Markdown file — `header-briefing/SKILL.md` — and all API calls are plain `curl`. To use it outside Claude Code, point your agent at that file as a rules / conventions / system-prompt fragment:

- **Cursor**: add `header-briefing/SKILL.md` as a project rule.
- **Aider**: `aider --read header-briefing/SKILL.md` (or add to `CONVENTIONS.md`).
- **OpenAI Codex CLI / Goose / Cline / other**: paste or reference the file contents in your agent's instructions.

The frontmatter (`name`, `description`, `allowed-tools`) is Claude-Code-specific and is safely ignored by other harnesses.

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
| `HEADER_LANGUAGE` | No | Language for output rendering (e.g. `Turkish`, `Spanish`). Defaults to English. The agent translates the presentation; API content stays English. |

## License

MIT — see [LICENSE](LICENSE) for details.
