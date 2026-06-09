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
# Bash 3.2 (macOS default) mis-parses `case` inside command substitution, so
# evaluate it as its own statement.
case "$est" in ''|*[!0-9]*) est_numeric=no ;; *) est_numeric=yes ;; esac
assert_eq "yes" "$est_numeric" \
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

# ── model staleness ───────────────────────────────────────────
# the main sandbox pins sonnet-4-6 (current) → no MODEL-STALE line.
assert_not_contains "$H" "MODEL-STALE" "a current model id is not flagged stale"
sb_stale="$(make_sandbox)"; rstale="$sb_stale/r"; mkdir -p "$rstale/.claude"
printf '{ "model": "claude-3-5-sonnet-20241022" }\n' > "$rstale/.claude/settings.json"
printf '# x\n' > "$rstale/CLAUDE.md"
Hstale="$(HOME="$sb_stale" "$AU" harness --repo "$rstale")"
assert_contains "$Hstale" $'MODEL-STALE\tclaude-3-5-sonnet-20241022' \
  "a Claude 3.x model id is flagged as a superseded tier"
printf '{ "model": "claude-opus-4-1-20250805" }\n' > "$rstale/.claude/settings.json"
assert_contains "$(HOME="$sb_stale" "$AU" harness --repo "$rstale")" $'MODEL-STALE\tclaude-opus-4-1' \
  "early Opus 4 (4.1) is flagged as superseded by Opus 4.5+"

# ── model upgrade opportunity (newer same-family model — not debt) ──
printf '{ "model": "claude-opus-4-7" }\n' > "$rstale/.claude/settings.json"
Hup="$(HOME="$sb_stale" "$AU" harness --repo "$rstale")"
assert_contains "$Hup" $'MODEL-UPGRADE\tclaude-opus-4-7\tclaude-opus-4-8' \
  "Opus 4.7 → MODEL-UPGRADE names Opus 4.8 as the newer same-family candidate"
assert_not_contains "$Hup" "MODEL-STALE" \
  "a current (4.7) model is an upgrade opportunity, not stale debt"
printf '{ "model": "claude-opus-4-8" }\n' > "$rstale/.claude/settings.json"
assert_not_contains "$(HOME="$sb_stale" "$AU" harness --repo "$rstale")" "MODEL-UPGRADE" \
  "the current flagship (Opus 4.8) is not flagged for upgrade"
printf '{ "model": "claude-opus-4-1-20250805" }\n' > "$rstale/.claude/settings.json"
assert_not_contains "$(HOME="$sb_stale" "$AU" harness --repo "$rstale")" "MODEL-UPGRADE" \
  "a superseded tier is flagged STALE, not as an upgrade opportunity"

# ── detection: no pinned model → fall back to the most recent transcript model ──
# (so plain /header offers the upgrade even when the user rides the default alias)
# Real Claude Code nests transcripts one level per project:
# ~/.claude/projects/<project-key>/<session>.jsonl — the fixture MUST be nested,
# or the test passes against a layout that doesn't exist (the 0.21.1 regression).
sb_tx="$(make_sandbox)"; rtx="$sb_tx/r"; mkdir -p "$rtx" "$sb_tx/.claude/projects/-home-u-proj"
printf '# x\n' > "$rtx/CLAUDE.md"   # NO .claude/settings.json → unpinned
printf '{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{}}}\n' > "$sb_tx/.claude/projects/-home-u-proj/s.jsonl"
Htx="$(HOME="$sb_tx" "$AU" harness --repo "$rtx")"
assert_contains "$Htx" $'MODEL\tclaude-opus-4-7' \
  "MODEL is detected from the most recent NESTED transcript when settings pin nothing"
assert_contains "$Htx" $'MODEL-UPGRADE\tclaude-opus-4-7\tclaude-opus-4-8' \
  "MODEL-UPGRADE fires off the transcript-detected model (plain /header offers it unpinned)"
# Newest-wins across layouts: an older flat-layout file must not shadow the
# newer nested one (and flat stays tolerated for back-compat).
printf '{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{}}}\n' > "$sb_tx/.claude/projects/old-flat.jsonl"
touch -t 202001010000 "$sb_tx/.claude/projects/old-flat.jsonl"
assert_contains "$(HOME="$sb_tx" "$AU" harness --repo "$rtx")" $'MODEL\tclaude-opus-4-7' \
  "the newest transcript wins across nested + flat layouts"

# ── @import following + stale references ──────────────────────
sb_imp="$(make_sandbox)"; rimp="$sb_imp/r"; mkdir -p "$rimp/docs" "$rimp/scripts"
printf 'x\n' > "$rimp/scripts/deploy.sh"          # exists → not stale
printf 'imported guidance\n' > "$rimp/docs/extra.md"
cat > "$rimp/CLAUDE.md" <<'MD'
# Project
See `scripts/deploy.sh` to deploy and `scripts/gone.sh` for cleanup.
Conventions live at `path/to/placeholder.md` (a doc placeholder, ignore).
@docs/extra.md
@docs/missing.md
MD
Himp="$(HOME="$sb_imp" "$AU" harness --repo "$rimp")"
assert_contains "$Himp" $'IMPORT\t'"$rimp/CLAUDE.md"$'\t'"$rimp/docs/extra.md" \
  "a resolvable @import emits an IMPORT edge"
assert_contains "$Himp" "FILE	$rimp/docs/extra.md" \
  "an @imported file is scanned as an always-loaded FILE (counts toward the per-turn sum)"
assert_contains "$Himp" $'STALE-REF\t'"$rimp/CLAUDE.md"$'\t5\t@docs/missing.md' \
  "an unresolvable @import is a STALE-REF"
assert_contains "$Himp" $'STALE-REF\t'"$rimp/CLAUDE.md"$'\t2\tscripts/gone.sh' \
  "a backtick path that no longer exists is a STALE-REF"
assert_not_contains "$Himp" "scripts/deploy.sh	referenced path not found" \
  "a backtick path that still exists is not flagged"
assert_not_contains "$Himp" "path/to/placeholder.md	referenced path not found" \
  "a path/to/ documentation placeholder is not flagged"

# ── nested CLAUDE.md (on-demand, reported apart from always-loaded) ──
mkdir -p "$rimp/sub"; printf '# nested rules\n' > "$rimp/sub/CLAUDE.md"
Hnest="$(HOME="$sb_imp" "$AU" harness --repo "$rimp")"
assert_contains "$Hnest" "NESTED	$rimp/sub/CLAUDE.md" "a subdir CLAUDE.md is reported as NESTED"
assert_not_contains "$Hnest" "NESTED	$rimp/CLAUDE.md" "the repo-root CLAUDE.md is not double-counted as NESTED"

# ── hooks (arbitrary shell on agent events) ───────────────────
sb_hk="$(make_sandbox)"; rhk="$sb_hk/r"; mkdir -p "$rhk/.claude"; printf '# x\n' > "$rhk/CLAUDE.md"
cat > "$rhk/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo guard" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "notify-send done" } ] } ]
  }
}
JSON
Hhk="$(HOME="$sb_hk" "$AU" harness --repo "$rhk")"
assert_contains "$Hhk" $'HOOK\tPreToolUse\techo guard' "a PreToolUse hook command is surfaced"
assert_contains "$Hhk" $'HOOK\tStop\tnotify-send done' "a Stop hook command is surfaced"
# a settings file with no hooks key yields no HOOK lines
printf '{ "model": "claude-opus-4-8" }\n' > "$rhk/.claude/settings.json"
assert_not_contains "$(HOME="$sb_hk" "$AU" harness --repo "$rhk")" $'HOOK\t' \
  "settings with no hooks key → no HOOK line"
# an mcpServers "command" sharing the file is NOT a hook (no "type":"command" anchor)
cat > "$rhk/.claude/settings.json" <<'JSON'
{
  "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "real-hook" } ] } ] },
  "mcpServers": { "fs": { "command": "npx", "args": ["-y", "server"] } }
}
JSON
Hmcp="$(HOME="$sb_hk" "$AU" harness --repo "$rhk")"
assert_contains "$Hmcp" $'HOOK\tStop\treal-hook' "the real hook command is still surfaced"
assert_not_contains "$Hmcp" "npx" "an mcpServers command is not misattributed as a hook"

# ── installed skills (supply-chain + execution surface) ───────
sb_sk="$(make_sandbox)"; rsk="$sb_sk/r"
mkdir -p "$rsk/.claude/skills/withbin/bin" "$rsk/.claude/skills/nobin" "$sb_sk/.claude/skills/usertool/bin"
printf '# x\n' > "$rsk/CLAUDE.md"
printf '#!/bin/sh\n' > "$rsk/.claude/skills/withbin/bin/run"; chmod +x "$rsk/.claude/skills/withbin/bin/run"
printf '# skill\n' > "$rsk/.claude/skills/nobin/SKILL.md"
printf '#!/bin/sh\n' > "$sb_sk/.claude/skills/usertool/bin/x"
Hsk="$(HOME="$sb_sk" "$AU" harness --repo "$rsk")"
assert_contains "$Hsk" $'SKILL\twithbin\t'"$rsk/.claude/skills/withbin"$'\tyes\trepo' \
  "a repo skill carrying bin scripts → SKILL has-bin yes, scope repo"
assert_contains "$Hsk" $'SKILL\tnobin\t'"$rsk/.claude/skills/nobin"$'\tno\trepo' \
  "a repo skill with no bin → SKILL has-bin no"
assert_contains "$Hsk" $'SKILL\tusertool\t'"$sb_sk/.claude/skills/usertool"$'\tyes\tuser' \
  "a user-scope skill is reported with scope user"

# ── briefing-supplied debt patterns ───────────────────────────
sb_bp="$(make_sandbox)"; rbp="$sb_bp/r"; hh="$sb_bp/.header"; mkdir -p "$rbp" "$hh"
printf 'Please be very careful and double-check everything.\n' > "$rbp/CLAUDE.md"
# well-formed extra pattern + one malformed (4 fields) that must be skipped
printf 'over-caution\tbe very careful|double.?check everything\tBriefing-flagged over-caution.\n' > "$hh/patterns.tsv"
printf 'bad\tregex\twhy\textra-field-should-skip\n' >> "$hh/patterns.tsv"
Pbp="$(HEADER_HOME="$hh" HOME="$sb_bp" "$AU" patterns)"
assert_contains "$Pbp" "over-caution" "patterns lists a briefing-supplied id"
assert_not_contains "$Pbp" "bad " "a malformed (4-field) briefing pattern is skipped from the listing"
Hbp="$(HEADER_HOME="$hh" HOME="$sb_bp" "$AU" harness --repo "$rbp")"
assert_contains "$Hbp" $'\tover-caution\t' "a briefing-supplied pattern produces a HIT in the harness scan"

# ── cost (cost-aware audit) ───────────────────────────────────
sb_co="$(make_sandbox)"
cat > "$sb_co/usage.jsonl" <<'JSONL'
{"model":"claude-opus-4-8","input_tokens":200000,"output_tokens":80000,"ts":"2026-05-21T10:00:00Z"}
{"model":"claude-opus-4-8","input_tokens":100000,"output_tokens":50000,"ts":"2026-05-20T10:00:00Z"}
{"model":"claude-haiku-4-5","input_tokens":50000,"output_tokens":10000,"ts":"2026-05-22T10:00:00Z"}
JSONL
C="$(HOME="$sb_co" "$AU" cost --input "$sb_co/usage.jsonl")"
assert_contains "$C" $'COST-SCOPE\tinput\t' "cost --input labels its scope as input"
assert_contains "$C" $'SPEND-TOTAL\t' "cost emits a SPEND-TOTAL line"
assert_contains "$C" $'SPEND\tclaude-opus-4-8\t' "cost breaks spend down by model"
assert_contains "$C" $'ROUTE-CANDIDATE\tclaude-opus-4-8\t' \
  "cost names the top-spend model as the model-routing candidate"
# the route candidate is the costliest model, not merely the first or last seen
rc_model="$(printf '%s\n' "$C" | awk -F'\t' '$1=="ROUTE-CANDIDATE"{print $2}')"
assert_eq "claude-opus-4-8" "$rc_model" "ROUTE-CANDIDATE is the costliest model"
# a missing input file degrades to a NOTE, never an error row
assert_contains "$(HOME="$sb_co" "$AU" cost --input "$sb_co/nope.jsonl")" $'NOTE\tcost\t' \
  "cost with a missing input emits a NOTE, not a crash"

# ── cost: repo-scoped by default, no cross-project leakage (HEA-435) ──
# Two projects under ~/.claude/projects keyed by repo path (Claude Code's own
# convention: abs path → non-alphanumerics replaced by '-'). repoA spends little
# (haiku); repoB spends a lot (opus). A default audit of repoA must report ONLY
# repoA's spend — the large global total must never leak in.
sb_sc="$(make_sandbox)"; repoA="$sb_sc/repoA"; repoB="$sb_sc/repoB"
mkdir -p "$repoA" "$repoB"
keyA="$(printf '%s' "$repoA" | sed 's/[^A-Za-z0-9]/-/g')"
keyB="$(printf '%s' "$repoB" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$sb_sc/.claude/projects/$keyA" "$sb_sc/.claude/projects/$keyB"
printf '{"model":"claude-haiku-4-5","input_tokens":50000,"output_tokens":10000,"ts":"2026-05-22T10:00:00Z"}\n' \
  > "$sb_sc/.claude/projects/$keyA/a.jsonl"
printf '{"model":"claude-opus-4-8","input_tokens":2000000,"output_tokens":800000,"ts":"2026-05-21T10:00:00Z"}\n' \
  > "$sb_sc/.claude/projects/$keyB/b.jsonl"

SCA="$(HOME="$sb_sc" "$AU" cost --repo "$repoA")"
assert_contains "$SCA" $'COST-SCOPE\trepo\t'"$repoA" "default cost is scoped to the current repo"
assert_contains "$SCA" $'COST-INPUT\t'"$sb_sc/.claude/projects/$keyA"$'\t1\tfiles' \
  "cost names the repo-scoped transcript dir it priced"
assert_contains "$SCA" $'SPEND\tclaude-haiku-4-5\t' "repo-scoped cost prices this repo's models"
assert_not_contains "$SCA" $'SPEND\tclaude-opus-4-8\t' \
  "the other project's opus spend does NOT leak into this repo's report"
assert_contains "$SCA" $'COST-HARNESS\tclaude\tclaude-transcripts' "cost labels the active harness"

# A repo with no matching transcript dir → NOTE, and crucially NO SPEND (never a
# silent machine-wide aggregate).
SCN="$(HOME="$sb_sc" "$AU" cost --repo "$sb_sc/repoNone")"
assert_contains "$SCN" $'NOTE\tcost\t' "a repo with no transcripts degrades to a NOTE"
assert_not_contains "$SCN" $'SPEND-TOTAL\t' "no-data repo never falls back to a global aggregate"

# --all-projects is the explicit machine-wide opt-in: labeled global, totals cover
# both projects (so opus reappears).
SCG="$(HOME="$sb_sc" "$AU" cost --all-projects)"
assert_contains "$SCG" $'COST-SCOPE\tglobal\t' "--all-projects labels its scope as global"
assert_contains "$SCG" $'SPEND\tclaude-opus-4-8\t' "--all-projects aggregates every project"

# Codex harness over Claude transcripts is a cross-harness mismatch: label it and
# flag it so the presentation downgrades the routing recommendation.
SCX="$(HOME="$sb_sc" "$AU" cost --repo "$repoA" --harness codex)"
assert_contains "$SCX" $'COST-HARNESS\tcodex\tclaude-transcripts' "Codex harness is labeled on the cost source"
assert_contains "$SCX" $'COST-NOTE\tharness-mismatch\t' "Codex over Claude transcripts flags a harness mismatch"
# the mismatch NOTE is suppressed under the explicit cross-harness opt-in
assert_not_contains "$(HOME="$sb_sc" "$AU" cost --all-projects --harness codex)" \
  $'COST-NOTE\tharness-mismatch\t' "--all-projects suppresses the harness-mismatch NOTE (explicit opt-in)"

# ── unknown subcommand → exit 1 ───────────────────────────────
HOME="$sb" "$AU" bogus >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "unknown subcommand → exit 1"

t_done
