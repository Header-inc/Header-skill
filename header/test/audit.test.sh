#!/usr/bin/env bash
# test/audit.test.sh — bin/header-audit. Builds a sandbox repo with planted debt
# and manifests, then asserts on the structured scan output. HOME is sandboxed so
# the user-global ~/.claude/CLAUDE.md never bleeds in.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

AU="$SKILL_DIR/bin/header-audit"

# ── sandbox repo with planted prompt debt + manifests ─────────
sb="$(make_sandbox)"; repo="$sb/repo"; mkdir -p "$repo/.claude/commands"
cat > "$repo/CLAUDE.md" <<'MD'
# Project
You are an expert Go engineer. Always think step by step before answering.
Do not hallucinate. Respond only in JSON.
Use tabs and run gofmt.
MD
cat > "$repo/.claude/settings.json" <<'JSON'
{ "model": "claude-sonnet-4-6" }
JSON
printf '{"name":"x","dependencies":{"chalk":"^5"}}\n' > "$repo/package.json"
printf 'requests==2.0\n' > "$repo/requirements.txt"

# ── patterns ──────────────────────────────────────────────────
pats="$(HOME="$sb" "$AU" patterns)"
assert_contains "$pats" "step-by-step" "patterns lists the step-by-step debt id"
assert_contains "$pats" "no-hallucinate" "patterns lists the no-hallucinate debt id"

# ── harness scan ──────────────────────────────────────────────
H="$(HOME="$sb" "$AU" harness --repo "$repo")"
assert_contains "$H" "MODEL	claude-sonnet-4-6" "harness reports the declared model"
assert_contains "$H" "FILE	$repo/CLAUDE.md" "harness reports CLAUDE.md as a file"
assert_contains "$H" "	step-by-step	" "harness flags the step-by-step pattern hit"
assert_contains "$H" "	role-puffery	" "harness flags role puffery"
assert_contains "$H" "	no-hallucinate	" "harness flags the don't-hallucinate line"
assert_contains "$H" "	json-nag	" "harness flags JSON-format nagging"
# token estimate present and numeric (bytes/4)
fileline="$(printf '%s\n' "$H" | grep "FILE	$repo/CLAUDE.md")"
est="$(printf '%s' "$fileline" | awk -F'\t' '{print $4}')"
assert_eq "yes" "$(case "$est" in ''|*[!0-9]*) echo no ;; *) echo yes ;; esac)" \
  "harness FILE line carries a numeric token estimate"

# a clean repo yields no HITs
clean="$sb/clean"; mkdir -p "$clean"
printf '# Clean\nUse tabs.\n' > "$clean/CLAUDE.md"
assert_not_contains "$(HOME="$sb" "$AU" harness --repo "$clean")" "HIT	" \
  "a debt-free CLAUDE.md produces no pattern hits"

# ── deps scan ─────────────────────────────────────────────────
D="$(HOME="$sb" "$AU" deps --repo "$repo")"
assert_contains "$D" "ECOSYSTEM	npm	$repo/package.json" "deps detects the npm ecosystem"
assert_contains "$D" "ECOSYSTEM	python	$repo/requirements.txt" "deps detects the python ecosystem"
assert_contains "$D" "GATE	npm	absent" "no .npmrc → npm cooldown gate absent"

# add the gate → now present
HOME="$sb" "$AU" gate npm 7 > "$repo/.npmrc"
assert_contains "$(HOME="$sb" "$AU" deps --repo "$repo")" "GATE	npm	present" \
  "an .npmrc with min-release-age → gate present"

# ── gate snippets ─────────────────────────────────────────────
gnpm="$(HOME="$sb" "$AU" gate npm 14)"
assert_contains "$gnpm" "min-release-age=14" "gate npm parameterizes the day count"
assert_contains "$gnpm" "npm >= 11.10" "gate npm states the minimum npm version"
gpip="$(HOME="$sb" "$AU" gate pip 7)"
assert_contains "$gpip" "uploaded-prior-to P7D" "gate pip emits the ISO-8601 cooldown flag"
assert_contains "$gpip" "pip>=26.1" "gate pip states the minimum pip version"

# ── bash tool security posture ────────────────────────────────
sb2="$(make_sandbox)"; r="$sb2/r"; mkdir -p "$r/.claude"
cat > "$r/.claude/settings.json" <<'J'
{
  "permissions": { "defaultMode": "bypassPermissions" }
}
J
assert_contains "$(HOME="$sb2" "$AU" harness --repo "$r")" $'SECURITY\tbash\tbypass' \
  "bypassPermissions → SECURITY bash bypass (no gating)"
cat > "$r/.claude/settings.json" <<'J'
{
  "permissions": { "deny": [ "Bash(curl:*)", "Bash(rm:*)" ] }
}
J
assert_contains "$(HOME="$sb2" "$AU" harness --repo "$r")" $'SECURITY\tbash\tdenylist' \
  "a Bash deny-list → denylist (blacklist)"
cat > "$r/.claude/settings.json" <<'J'
{
  "permissions": { "allow": [ "Bash(npm run test:*)" ], "deny": [ "Read(./.env)" ] }
}
J
Hsec="$(HOME="$sb2" "$AU" harness --repo "$r")"
assert_contains "$Hsec" $'SECURITY\tbash\tallowlist' \
  "a Bash allow-list → allowlist (whitelist); a non-Bash deny doesn't flip it"
assert_contains "$Hsec" $'SECURITY-DETAIL\tallow\tBash(npm run test:*)' \
  "allow-list entry detail is surfaced"
cat > "$r/.claude/settings.json" <<'J'
{
  "permissions": { "allow": [ "Read(./src/**)" ] }
}
J
assert_not_contains "$(HOME="$sb2" "$AU" harness --repo "$r")" $'SECURITY\tbash' \
  "settings with no Bash rules → no SECURITY line"

# ── unknown subcommand → exit 1 ───────────────────────────────
HOME="$sb" "$AU" bogus >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "unknown subcommand → exit 1"

t_done
