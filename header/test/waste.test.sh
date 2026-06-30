#!/usr/bin/env bash
# test/waste.test.sh — header-audit waste: transcript-mined usage accounting.
# Fixtures use the REAL nested transcript layout (~/.claude/projects/<key>/<sess>.jsonl)
# and both observed tool_result field orders (is_error before AND after tool_use_id).
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

AU="$SKILL_DIR/bin/header-audit"

# ── fixture: a repo + a sandboxed HOME with nested transcripts ──
sb="$(make_sandbox)"
repo="$sb/r"; mkdir -p "$repo/.claude/skills/usedskill" "$repo/.claude/skills/deadskill"
cat > "$repo/.claude/skills/usedskill/SKILL.md" <<'MD'
---
name: usedskill
description: a skill the transcripts invoke
---
body
MD
cat > "$repo/.claude/skills/deadskill/SKILL.md" <<'MD'
---
name: deadskill
description: a skill nothing ever invokes
---
body
MD
# repo MCP config: alpha is used in the transcripts, beta never is
cat > "$repo/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "alpha": { "command": "alpha-server" },
    "beta":  { "command": "beta-server" }
  }
}
JSON

# Transcripts keyed like Claude Code keys them (repo path, non-alnum → '-').
key="$(printf '%s' "$repo" | sed 's/[^A-Za-z0-9]/-/g')"
tdir="$sb/home/.claude/projects/$key"
mkdir -p "$tdir"
cat > "$tdir/sess.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-06-01T10:00:00Z","message":{"content":[{"type":"tool_use","id":"toolu_aa1","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","timestamp":"2026-06-01T10:00:01Z","message":{"content":[{"tool_use_id":"toolu_aa1","type":"tool_result","content":"ok","is_error":false}]}}
{"type":"assistant","timestamp":"2026-06-01T10:00:02Z","message":{"content":[{"type":"tool_use","id":"toolu_aa2","name":"mcp__alpha__doit","input":{}}]}}
{"type":"user","timestamp":"2026-06-01T10:00:03Z","message":{"content":[{"type":"tool_result","content":"boom","is_error":true,"tool_use_id":"toolu_aa2"}]}}
{"type":"assistant","timestamp":"2026-06-01T10:00:04Z","message":{"content":[{"type":"tool_use","id":"toolu_aa3","name":"Skill","input":{"skill":"usedskill","args":""}}]}}
{"type":"user","timestamp":"2026-06-01T10:00:05Z","isCompactSummary":true,"message":{"content":"compacted"}}
{"type":"system","timestamp":"2026-06-01T10:00:05Z","subtype":"compact_boundary"}
EOF

W="$(HOME="$sb/home" "$AU" waste --repo "$repo")"
assert_contains "$W" $'WASTE-SCOPE\trepo\t'"$repo"        "default scope is this repo"
assert_contains "$W" $'WASTE-INPUT\t'"$tdir"              "the repo-scoped transcript dir is named"
assert_contains "$W" $'TOOL-USE\tBash\t1\t0'              "per-tool calls + errors are counted"
assert_contains "$W" $'TOOL-USE\tmcp__alpha__doit\t1\t1'  "is_error joins to the tool even when tool_use_id FOLLOWS is_error"
assert_contains "$W" $'MCP-SERVER\talpha\t1\t1'           "MCP tool calls roll up to the server"
assert_contains "$W" $'MCP-UNUSED\tbeta\t'                "a configured server with zero calls is flagged"
assert_not_contains "$W" $'MCP-UNUSED\talpha'             "a used server is not flagged"
assert_contains "$W" $'SKILL-USE\tusedskill\t1'           "Skill invocations are counted by name"
assert_contains "$W" $'SKILL-UNUSED\tdeadskill\t'         "a repo-installed skill never invoked here is flagged"
assert_not_contains "$W" $'SKILL-UNUSED\tusedskill'       "an invoked skill is not flagged"
assert_contains "$W" $'COMPACTIONS\t1\t'                  "summary + boundary markers count as ONE compaction (max, not sum)"
# (the always-loaded skill / registry context tax moved to `harness` in 0.37.1 —
# see audit.test.sh; waste no longer emits SKILL-TAX / CONTEXT-TAX.)
assert_not_contains "$W" $'SKILL-TAX\t'   "the skill frontmatter tax is no longer a waste row (moved to harness)"
assert_not_contains "$W" $'CONTEXT-TAX\t' "the context tax is no longer a waste row (moved to harness)"

# user-scope skills: never flagged unused (they serve other repos).
mkdir -p "$sb/home/.claude/skills/globalskill"
cat > "$sb/home/.claude/skills/globalskill/SKILL.md" <<'MD'
---
name: globalskill
description: serves every project on the machine
---
body
MD
W2="$(HOME="$sb/home" "$AU" waste --repo "$repo")"
assert_not_contains "$W2" $'SKILL-UNUSED\tglobalskill'  "user-scope skills are never flagged unused"

# --since filters out lines before the cutoff.
W3="$(HOME="$sb/home" "$AU" waste --repo "$repo" --since 2026-06-01T10:00:04Z)"
assert_not_contains "$W3" $'TOOL-USE\tBash'      "--since drops lines before the cutoff"
assert_contains "$W3" $'SKILL-USE\tusedskill\t1' "--since keeps lines at/after the cutoff"

# Scope honesty (HEA-435): no transcripts → NOTE, never a silent aggregate.
sb2="$(make_sandbox)"; mkdir -p "$sb2/r2" "$sb2/home"
N="$(HOME="$sb2/home" "$AU" waste --repo "$sb2/r2")"
assert_contains "$N" $'NOTE\twaste\t' "missing transcript dir is a NOTE"
assert_not_contains "$N" "WASTE-SCOPE" "no silent fallback scope"

# --all-projects is the explicit global opt-in.
mkdir -p "$sb/home/.claude/projects/-some-other-proj"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_zz1","name":"Read","input":{}}]}}\n' \
  > "$sb/home/.claude/projects/-some-other-proj/s.jsonl"
G="$(HOME="$sb/home" "$AU" waste --repo "$repo" --all-projects)"
assert_contains "$G" $'WASTE-SCOPE\tglobal\t' "--all-projects labels the scope global"
assert_contains "$G" $'TOOL-USE\tRead\t1\t0'  "global scope aggregates other projects"

# --input prices an explicit file (testing seam, mirrors cost).
I="$(HOME="$sb/home" "$AU" waste --repo "$repo" --input "$tdir/sess.jsonl")"
assert_contains "$I" $'WASTE-SCOPE\tinput\t' "--input labels the scope input"
assert_contains "$I" $'TOOL-USE\tBash\t1\t0' "--input streams the given file"

# ── canonical ledger keys on recommendation-capable rows ──────
assert_contains "$W" $'MCP-UNUSED\tbeta\t'"$repo/.mcp.json"$'\tkey=waste-mcp-beta' \
  "MCP-UNUSED pre-mints key=waste-mcp-<server>"
assert_contains "$W" $'SKILL-UNUSED\tdeadskill\t'"$repo/.claude/skills/deadskill"$'\tkey=waste-skill-deadskill' \
  "SKILL-UNUSED pre-mints key=waste-skill-<name>"
assert_not_contains "$(printf '%s\n' "$W" | grep '^TOOL-USE')" "key=" \
  "TOOL-USE rows are evidence, not recommendations — no key"

# Exit-code hygiene: success paths exit 0.
HOME="$sb/home" "$AU" waste --repo "$repo" >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "waste exits 0 on success"
HOME="$sb2/home" "$AU" waste --repo "$sb2/r2" >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "the NOTE path exits 0 (degrade gracefully, not an error)"

t_done
