# Roadmap

Tracked follow-ups and deferred decisions. See [CHANGELOG.md](CHANGELOG.md) for what's shipped.

## Planned

### Experiments engine (`header-experiment`)

Header's north star: an optimization layer for AI coding agents. The loop —
**generate hypotheses → run experiments → keep the statistically significant wins →
merge them back into the harness config** — run continuously against a customer's
codebase. Feasible now because agentic coding collapses an A/B variant from
engineering-hours to **tokens**, so continuous experimentation gets affordable exactly
as token discipline becomes mandatory.

It builds on what's already shipped: the **briefing reader** (the wedge that feeds
hypotheses — new models, dependency advisories), **`header-cost`** (the
measurement / billing meter), and now an **MVP `header-experiment` (beta, local-only)**
covering `define / validate / run / analyze / report` with worktree-isolated runs,
paired-by-task bootstrap CIs, an A/A noise-floor mode, and the §6.5 cost-superiority +
success non-inferiority decision rule.

**Next on this track (not yet built):**

- **Verifiers & task mining from git history** (§11 of the design) — turn the
  customer's own test suite into the oracle; mine FAIL_TO_PASS commits into task
  specs so users don't hand-write tasks.
- **`header-experiment merge`** — apply a significant win to the harness behind a
  consent gate, with the diff shown first.
- **Cross-customer proven-changes library** — consent-gated aggregate submit of
  effect size + change category (no code, no paths); pulled back into the audit as
  "deleting this pattern is proven to save ~X% across N repos." This is the moat.
- **`header-experiment run` schedule integration** — close the loop with the
  briefing schedule: "new Opus dropped → queue a migration experiment."

Full design — measurement, the A/A noise floor, statistics, verifiers & task mining,
the local / Header-infra / hybrid architecture, build order, and the CLI spec — lives
in [docs/experiments-design.md](docs/experiments-design.md).

## Deferred

### Claude Code `/plugin` marketplace distribution

**Status:** deferred (2026-05-22). Install today is `npx skills` (README Option A) plus the `curl | sh` / clone paths; updates run through the skill's own version-endpoint check.

Supporting `/plugin marketplace add Header-inc/Header-skill` was evaluated and held off:

- **No auto-update benefit by default.** Third-party marketplaces have auto-update **off by default** in Claude Code — users would have to opt in per-marketplace, so it doesn't beat our existing updater out of the box.
- **Conflicts with our self-update.** A plugin installs to `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` — a different location from `~/.claude/skills/header/`, where `install.sh`, `npx skills -g`, and the self-update all write. Installing both would duplicate the skill and split its command namespace (`/header` vs `/header:…`).
- **Our updater is more capable here.** `bin/header-update-check` gates on the Header API's minimum-supported version (`UPDATE_REQUIRED`); the marketplace has no API-version gate.

**To adopt later:**
1. Add `.claude-plugin/marketplace.json` (+ a `plugin.json`) pointing at the `header` skill.
2. Teach the skill to detect plugin-mode (e.g. when its own directory resolves under `~/.claude/plugins/`) and **stand down its self-update** there, deferring to the marketplace.
3. Document `/plugin marketplace add` + `/plugin install` as a Claude Code option, noting users must enable marketplace auto-update for it to refresh on its own.
