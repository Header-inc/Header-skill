#!/usr/bin/env bash
# test/rails.test.sh — bin/header-audit {rails,rail}. Determinism-rail detection
# and the scaffold printer. Builds sandbox git repos, asserts on the structured
# scan output, and on the printed scaffolds. HOME is sandboxed so the user's real
# git/global config never bleeds in. Never executes the gate (no black/pytest
# dependency) — it only inspects the printed template, like the gate examples.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

AU="$SKILL_DIR/bin/header-audit"

# small helper: a fresh git repo under a sandbox
_mkrepo() { local d="$1"; mkdir -p "$d"; ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t ); }

# ── bare python repo, no rails ────────────────────────────────
sb="$(make_sandbox)"; repo="$sb/repo"; _mkrepo "$repo"
printf 'requests==2.0\n' > "$repo/requirements.txt"
R="$(HOME="$sb" "$AU" rails --repo "$repo")"
assert_contains "$R" $'RAIL-ENV\tecosystem\tpython' "primary ecosystem detected from requirements.txt"
assert_contains "$R" $'RAIL-ENV\tgit-remote\tno'    "a repo with no remote → git-remote no"
assert_contains "$R" $'RAIL-ENV\thooks-path\tunset' "no core.hooksPath → hooks-path unset"
assert_contains "$R" $'RAIL-ENV\tclaude\tno'        "no .claude dir → claude no"
assert_contains "$R" $'RAIL-ENV\ttests\tnone'       "no test suite → tests none"
assert_contains "$R" $'RAIL\tprecommit-gate\tabsent'   "no gate → precommit-gate absent"
assert_contains "$R" $'RAIL\ttest-ratchet\tn/a'        "no tests → test-ratchet n/a (not absent)"
assert_contains "$R" $'RAIL\tcompound-memory\tabsent'  "no memory discipline → compound-memory absent"

# ── tests present but no gate → ratchet flips absent ──────────
mkdir -p "$repo/tests"; printf 'def test_a():\n    pass\n' > "$repo/tests/test_a.py"
R2="$(HOME="$sb" "$AU" rails --repo "$repo")"
assert_contains "$R2" $'RAIL-ENV\ttests\ttests/'      "tests/ dir → tests path reported"
assert_contains "$R2" $'RAIL\ttest-ratchet\tabsent'   "tests present, no ratchet → test-ratchet absent"

# ── git-native gate present → precommit-gate present ──────────
mkdir -p "$repo/.githooks"; printf '#!/bin/sh\n' > "$repo/.githooks/pre-commit"
assert_contains "$(HOME="$sb" "$AU" rails --repo "$repo")" $'RAIL\tprecommit-gate\tpresent\t.githooks/pre-commit' \
  "a committed .githooks/pre-commit → precommit-gate present"

# ── a ratchet signature in the gate script → test-ratchet present ──
printf '#!/bin/sh\n# RATCHET_OVERRIDE escape\n' > "$repo/.githooks/pre-commit"
assert_contains "$(HOME="$sb" "$AU" rails --repo "$repo")" $'RAIL\ttest-ratchet\tpresent' \
  "a gate carrying a ratchet signature → test-ratchet present"

# ── PreToolUse gate hook (no git hook) → precommit-gate present ──
sb2="$(make_sandbox)"; r2="$sb2/r"; _mkrepo "$r2"; mkdir -p "$r2/.claude"
cat > "$r2/.claude/settings.json" <<'J'
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "scripts/pre-commit-gate.sh" } ] } ] } }
J
PT="$(HOME="$sb2" "$AU" rails --repo "$r2")"
assert_contains "$PT" $'RAIL\tprecommit-gate\tpresent\tPreToolUse gate hook' \
  "a PreToolUse hook that runs the gate → precommit-gate present"
assert_contains "$PT" $'RAIL-ENV\tclaude\tyes' "a .claude dir → claude yes"
# a PreToolUse hook unrelated to commits does NOT count as a gate
cat > "$r2/.claude/settings.json" <<'J'
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo hi" } ] } ] } }
J
assert_contains "$(HOME="$sb2" "$AU" rails --repo "$r2")" $'RAIL\tprecommit-gate\tabsent' \
  "an unrelated PreToolUse hook is NOT counted as a commit gate"

# ── compound-memory detection (dir, MEMORY.md, skill) ─────────
sb3="$(make_sandbox)"; r3="$sb3/r"; _mkrepo "$r3"
mkdir -p "$r3/.claude/memory"; printf '# note\n' > "$r3/.claude/memory/pitfall_x.md"
assert_contains "$(HOME="$sb3" "$AU" rails --repo "$r3")" $'RAIL\tcompound-memory\tpresent\t.claude/memory/' \
  ".claude/memory/*.md → compound-memory present"
rm -rf "$r3/.claude/memory"; printf '# Memory\n' > "$r3/MEMORY.md"
assert_contains "$(HOME="$sb3" "$AU" rails --repo "$r3")" $'RAIL\tcompound-memory\tpresent\tMEMORY.md' \
  "a root MEMORY.md → compound-memory present"

# ── ecosystem precedence + git-remote yes ─────────────────────
sb4="$(make_sandbox)"; r4="$sb4/r"; _mkrepo "$r4"
printf '{"name":"x"}\n' > "$r4/package.json"; printf 'requests==2.0\n' > "$r4/requirements.txt"
( cd "$r4" && git remote add origin https://example.com/x.git )
R4="$(HOME="$sb4" "$AU" rails --repo "$r4")"
assert_contains "$R4" $'RAIL-ENV\tecosystem\tpython' "python takes precedence over npm as the primary stack"
assert_contains "$R4" $'RAIL-ENV\tecosystem-all\t' "ecosystem-all line is present"
assert_contains "$R4" $'RAIL-ENV\tgit-remote\tyes' "a configured remote → git-remote yes"
# unknown ecosystem when no manifest is present
sb5="$(make_sandbox)"; r5="$sb5/r"; _mkrepo "$r5"
assert_contains "$(HOME="$sb5" "$AU" rails --repo "$r5")" $'RAIL-ENV\tecosystem\tunknown' \
  "no manifest → ecosystem unknown"

# ── rail printer: precommit-gate, python, both ────────────────
G="$(HOME="$sb" "$AU" rail precommit-gate --ecosystem python --delivery both)"
assert_contains "$G" "scripts/pre-commit-gate.sh" "gate names the install path"
assert_contains "$G" "pytest" "python gate runs pytest"
assert_contains "$G" "black" "python gate runs black"
assert_contains "$G" "import shlex" "gate carries the shlex git-commit detector verbatim"
assert_contains "$G" "RATCHET_OVERRIDE" "ratchet is included by default (--ratchet on)"
assert_contains "$G" ".githooks/pre-commit" "delivery both prints the git-native wiring"
assert_contains "$G" "PreToolUse" "delivery both prints the Claude Code wiring"
assert_contains "$G" "HEADER_GATE_FORCE=1" "the git-native wiring sets HEADER_GATE_FORCE"

# delivery selection is honored
GG="$(HOME="$sb" "$AU" rail precommit-gate --ecosystem python --delivery git)"
assert_contains "$GG" ".githooks/pre-commit" "delivery git prints the git wiring"
assert_not_contains "$GG" "===== WIRING (Claude Code PreToolUse" "delivery git omits the PreToolUse wiring"
GP="$(HOME="$sb" "$AU" rail precommit-gate --ecosystem python --delivery pretooluse)"
assert_contains "$GP" "===== WIRING (Claude Code PreToolUse" "delivery pretooluse prints the PreToolUse wiring"
assert_not_contains "$GP" "===== WIRING (git-native" "delivery pretooluse omits the git wiring"

# ratchet off omits the ratchet
GO="$(HOME="$sb" "$AU" rail precommit-gate --ecosystem python --ratchet off)"
assert_not_contains "$GO" "RATCHET_OVERRIDE" "--ratchet off excludes the ratchet block"

# unknown ecosystem → TODO placeholder, still a usable gate
GU="$(HOME="$sb" "$AU" rail precommit-gate --ecosystem cobol --delivery git)"
assert_contains "$GU" "TODO" "an unknown ecosystem prints a TODO placeholder block"
assert_contains "$GU" "import shlex" "an unknown-ecosystem gate still carries the commit detector"

# ── rail printer: test-ratchet (standalone block) ─────────────
TR="$(HOME="$sb" "$AU" rail test-ratchet)"
assert_contains "$TR" "Test ratchet" "test-ratchet prints the ratchet block"
# the corrected kwarg-only xfail arm (Finding 5) must be present
assert_contains "$TR" 'xfail\([[:space:]]*[a-zA-Z_]' "ratchet carries the corrected kwarg-only xfail regex"

# ── rail printer: compound-memory ─────────────────────────────
CM="$(HOME="$sb" "$AU" rail compound-memory)"
assert_contains "$CM" ".claude/skills/compound/SKILL.md" "compound-memory prints the skill file path"
assert_contains "$CM" "name: compound" "compound-memory prints the compound skill frontmatter"
assert_contains "$CM" ".claude/memory/MEMORY.md" "compound-memory prints the seed index path"

# ── errors ────────────────────────────────────────────────────
HOME="$sb" "$AU" rail bogus >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "an unknown rail name → exit 1"
HOME="$sb" "$AU" rail >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "rail with no name → exit 1"

t_done
