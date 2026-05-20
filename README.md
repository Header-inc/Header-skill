# Header Briefing Skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A skill for agentic coding tools that fetches intelligence briefings from [Header](https://joinheader.com) and surfaces recommendations relevant to your current project. Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but works in any agent with shell access (Cursor, Aider, OpenAI Codex CLI, Goose, and others) — the skill is plain `bash` and `curl`, with no build step and no runtime dependencies.

[Header](https://joinheader.com) generates intelligence briefings from curated RSS and YouTube sources covering AI agent frameworks, MCP, coding tools, and related topics.

## Installation

The skill is a small folder — `header-briefing/` (`SKILL.md` + `bin/` + `VERSION`) — installed into your agent's skills directory.

### Option A: One-command install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
```

Installs into `~/.claude/skills/header-briefing/` (and `~/.codex/skills/` if Codex is detected). Re-run any time to update.

### Option B: Clone and install

```bash
git clone https://github.com/Header-inc/Header-skill.git
cd Header-skill && ./install.sh
```

To update later: `cd Header-skill && git pull && ./install.sh`.

### Option C: Project-local (available only in one project)

```bash
git clone https://github.com/Header-inc/Header-skill.git
mkdir -p .claude/skills
cp -R Header-skill/header-briefing .claude/skills/header-briefing
```

Start a new Claude Code session (or restart your current one) to pick up the skill.

> **Note:** If you install both globally and in a project, the global version takes precedence and the project-local copy is silently ignored. Pick one method per skill name.

### Using with other harnesses (Cursor, Aider, Codex CLI, etc.)

The skill is a folder of plain `bash` + `curl` — no build step, no runtime dependencies. To use it outside Claude Code, install the `header-briefing/` folder where your agent looks for skills, or point your agent at `header-briefing/SKILL.md` directly:

- **Cursor**: add `header-briefing/SKILL.md` as a project rule.
- **Aider**: `aider --read header-briefing/SKILL.md` (or add to `CONVENTIONS.md`).
- **OpenAI Codex CLI**: `install.sh` installs into `~/.codex/skills/` automatically when `codex` is detected.
- **Goose / Cline / other**: reference the `SKILL.md` contents in your agent's instructions.

The frontmatter (`name`, `version`, `description`, `when_to_use`, `argument-hint`, `allowed-tools`) is Claude-Code-specific and is safely ignored by other harnesses. Body sections use a `**Claude Code only:**` callout for behaviors that depend on Claude Code features; other harnesses can read past those callouts safely.

**What works where.** The core briefing workflow runs in any agent with shell access. The enterprise features need more:

| Capability | Requirement |
|---|---|
| Public + authenticated briefings | Any agent with shell access (`bash` + `curl`) |
| Persisted config (`~/.header/config`) | The `bin/header-config` helper resolves — installed via `install.sh` or a folder copy |
| First-run welcome + signup onboarding | An interactive agent session (Claude Code, or an agentic Cursor / Aider / Codex session) |

If `bin/header-config` is not found, the skill runs in **classic mode** — the briefing workflow works exactly as before, with config and onboarding switched off. It prints a one-line notice so a partial install is visible rather than silent.

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

For briefings tailored to your specific project and tech stack you need a free Header account. On its first run (after delivering a briefing) the skill offers a quick signup walkthrough; you can also set it up yourself:

1. Sign up at [joinheader.com](https://joinheader.com) — free trial, no credit card
2. Create an API key with **read + write** access from **Settings ▸ API Keys** (write is required to create custom topics)
3. Make the key available to the skill — either export it:

   ```bash
   export HEADER_API_KEY="hdr_sk_..."
   ```

   or let the onboarding funnel save it to `~/.header/credentials` (a file readable only by you).

With an API key, you can:

- **Create custom topics** with goal descriptions tailored to your project
- **Generate briefings on demand** for any of your topics
- **Update goals** to refine focus areas and keywords over time
- **Check briefing status** for async generation (`IN_PROGRESS`, `COMPLETED`, `FAILED`)

## Configuration

Configuration comes from three places, highest priority first: **environment variable › `~/.header/config` › built-in default**. Environment variables always win.

### Environment variables

| Variable | Description |
|----------|-------------|
| `HEADER_API_KEY` | Header API key (`hdr_sk_...`) for authenticated workflows. Only needed for custom topics and on-demand briefing generation. |
| `HEADER_LANGUAGE` _(Beta)_ | Language for output rendering (e.g. `Turkish`, `Spanish`). Defaults to English. The agent translates the presentation; API content stays English. |
| `HEADER_DEFAULT_TOPIC` | Topic UUID used when no argument is passed. Defaults to the "Self Improving Agent" public topic. |
| `HEADER_STALENESS_DAYS` | Maximum briefing age (in days) before warning that content may be stale. Defaults to 7. |
| `HEADER_HOME` | Override the state directory. Defaults to `~/.header`. |
| `HEADER_NONINTERACTIVE` | Set to `1` for scheduled / unattended runs so onboarding prompts are suppressed (`CI=1` is treated the same way). |

### Persisted config (`~/.header/config`)

`bin/header-config` reads and writes a flat `key: value` file at `~/.header/config`, so a preference set once survives across sessions without re-exporting an environment variable. The skill's preamble calls it for you; to set a preference by hand, call the helper inside the installed skill folder:

```bash
~/.claude/skills/header-briefing/bin/header-config set language Turkish
~/.claude/skills/header-briefing/bin/header-config list
```

Recognized keys: `default_topic`, `language`, `staleness_days`, `auto_update`, `update_check`. Run the helper with `defaults` to see every key and its default value.

### State directory

The skill keeps a small amount of state under `~/.header/` (override with `HEADER_HOME`):

| File | Purpose |
|---|---|
| `config` | Persisted configuration (flat `key: value`). |
| `credentials` | Optional — your API key, saved by the onboarding funnel (`chmod 600`; read as data, never executed). |
| `.welcome-seen`, `.signup-state`, `.language-prompted` | Onboarding markers, so first-run prompts show exactly once. |
| `last-update-check`, `update-snoozed`, `version-info.json` | Update-check cache, snooze state, and the last version-endpoint response. |

## Updating

On each run the skill checks for a newer version against Header's version endpoint (cached; 5-second timeout; silent and harmless if the endpoint is unreachable). When a newer version is available it offers to update, and remembers your choice:

- **The prompt** offers Yes / Always / Not now / Never. "Always" sets `auto_update`; "Never" sets `update_check false`.
- **Auto-update:** `~/.claude/skills/header-briefing/bin/header-config set auto_update true` — future updates install silently.
- **Disable checks:** `~/.claude/skills/header-briefing/bin/header-config set update_check false`.
- **Update manually anytime** by re-running the installer:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
  ```

If Header ships a breaking API change, the version endpoint marks a minimum supported version; a skill older than that says so rather than failing silently. Updates install atomically and roll back on failure.

## Development

The skill is plain `bash` — the test suite has no dependencies:

```bash
cd header-briefing && ./test/run.sh
```

## License

MIT — see [LICENSE](LICENSE) for details.
