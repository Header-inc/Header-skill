#!/usr/bin/env bash
# test/retro.test.sh — bin/header-audit `retro`. Behavioral mining of the user's
# OWN transcripts: edit-thrash, failed-tool volume, git-workflow tells, and the
# DERIVED RETRO-CAP capability nudges that map demonstrated behavior to the
# practice that addresses it. Fixture-driven via --input; HOME sandboxed.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

AU="$SKILL_DIR/bin/header-audit"

# ── no transcripts for the repo → NOTE, never a silent global aggregate ──
sb0="$(make_sandbox)"; r0="$sb0/repo"; mkdir -p "$r0"
N="$(HOME="$sb0" "$AU" retro --repo "$r0")"
assert_contains "$N" $'NOTE\tretro' "no repo transcript dir → NOTE (never a silent global aggregate)"

# ── fixture: 5 edits to one file, 3 failed Bash calls, stash + 2 switches ──
sb="$(make_sandbox)"; repo="$sb/repo"; mkdir -p "$repo"
fix="$sb/s.jsonl"
{
  for i in 1 2 3 4 5; do
    printf '{"type":"assistant","timestamp":"2026-06-10T10:0%s:00Z","message":{"content":[{"type":"tool_use","id":"e%s","name":"Edit","input":{"file_path":"/x/repo/foo.ts","old_string":"a","new_string":"b"}}]}}\n' "$i" "$i"
  done
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"git stash && git checkout main"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"tool_use_id":"b1","type":"tool_result","is_error":true,"content":[{"type":"text","text":"fatal"}]}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b2","name":"Bash","input":{"command":"git checkout -b feat/x"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"tool_use_id":"b2","type":"tool_result","is_error":true,"content":[{"type":"text","text":"err"}]}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b3","name":"Bash","input":{"command":"npm test"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"tool_use_id":"b3","type":"tool_result","is_error":true,"content":[{"type":"text","text":"fail"}]}]}}'
} > "$fix"

R="$(HOME="$sb" "$AU" retro --repo "$repo" --input "$fix")"
assert_contains "$R" $'RETRO-SCOPE\tinput' "input scope reported"
assert_contains "$R" $'RETRO-THRASH\tfoo.ts\t5' "a file edited 5x surfaces as thrash"
assert_contains "$R" $'RETRO-FAILS\tBash\t3\t3' "3 failed Bash calls counted (errors/calls)"
assert_contains "$R" $'RETRO-GIT\tstash\t1' "git stash tell counted"
assert_contains "$R" $'RETRO-GIT\tbranch-switch\t2' "git checkout/switch tells counted"
assert_contains "$R" $'RETRO-CAP\tworktree' "branch juggling with no worktree → worktree nudge"
assert_contains "$R" "key=cap-worktree" "worktree cap carries its ledger key"
assert_contains "$R" $'RETRO-CAP\tguardrail' "repeated Bash failures → guardrail nudge"
assert_contains "$R" "key=cap-guardrail" "guardrail cap carries its ledger key"
assert_contains "$R" $'RETRO-CAP\tcompound' "gotchas + no committed memory → compound nudge"
assert_contains "$R" "key=cap-compound" "compound cap carries its ledger key"

# ── compound cap suppressed once .claude/memory has an entry ──
mkdir -p "$repo/.claude/memory"; printf '# x\n' > "$repo/.claude/memory/pitfall_x.md"
R2="$(HOME="$sb" "$AU" retro --repo "$repo" --input "$fix")"
assert_not_contains "$R2" $'RETRO-CAP\tcompound' "committed .claude/memory suppresses the compound nudge"
assert_contains "$R2" $'RETRO-CAP\tguardrail' "guardrail nudge still fires (independent of memory)"

# ── worktree cap suppressed when worktrees are already in use ──
fix2="$sb/s2.jsonl"; cat "$fix" > "$fix2"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b4","name":"Bash","input":{"command":"git worktree add ../wt"}}]}}' >> "$fix2"
R3="$(HOME="$sb" "$AU" retro --repo "$repo" --input "$fix2")"
assert_contains "$R3" $'RETRO-GIT\tworktree\t1' "git worktree usage is tracked"
assert_not_contains "$R3" $'RETRO-CAP\tworktree' "already using worktrees → no worktree nudge"

# ── thrash threshold: a lightly-edited file is below the bar ──
fix3="$sb/s3.jsonl"
{
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"z1","name":"Edit","input":{"file_path":"/x/bar.ts"}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"z2","name":"Edit","input":{"file_path":"/x/bar.ts"}}]}}'
} > "$fix3"
R4="$(HOME="$sb" "$AU" retro --repo "$repo" --input "$fix3")"
assert_not_contains "$R4" $'RETRO-THRASH\tbar.ts' "a file edited only twice is below the thrash threshold"

# ── level: technical register inference from the user's OWN typed prompts ──
techf="$sb/tech.jsonl"; bizf="$sb/biz.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"the regex in `header-audit` is wrong — fix the gsub in foo.ts and rerun pytest on test/run.sh"}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"refactor parseConfig() to handle the json schema; the commit broke the branch, git rebase onto main"}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"why does `npm test` fail at src/index.ts — check the async function and the stderr"}}'
} > "$techf"
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"make the pricing page clearer so customers convert better, this is for our launch"}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"the messaging needs to resonate with our audience and drive adoption and growth"}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"can we make the onboarding feel more premium so users stick around and retention improves"}}'
} > "$bizf"
LT="$(HOME="$sb" "$AU" level --input "$techf")"
assert_contains "$LT" $'LEVEL\ttechnical' "code-reference-dense prompts → technical register"
assert_contains "$LT" $'LEVEL-EVIDENCE\t' "a representative prompt is surfaced as evidence (grounds the confirm)"
LB="$(HOME="$sb" "$AU" level --input "$bizf")"
assert_contains "$LB" $'LEVEL\tbusiness' "outcome-framed prompts with no code refs → business register"
# array (tool_result) content is NOT a typed prompt — must not read as technical
arrf="$sb/arr.jsonl"
printf '%s\n' '{"type":"user","message":{"content":[{"tool_use_id":"x","type":"tool_result","content":[{"type":"text","text":"git commit refactor schema endpoint pytest"}]}]}}' > "$arrf"
LA="$(HOME="$sb" "$AU" level --input "$arrf")"
assert_contains "$LA" $'NOTE\tlevel' "tool_result (array) content is not a typed prompt → NOTE, no false read"

# ── plan-mode + corrections + harness label ──
sigf="$sb/sig.jsonl"
{
  printf '%s\n' '{"type":"permission-mode","permissionMode":"plan"}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"no, that is wrong — revert that"}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"actually use a different approach"}}'
} > "$sigf"
RS="$(HOME="$sb" "$AU" retro --repo "$repo" --input "$sigf")"
assert_contains "$RS" $'RETRO-HARNESS\tclaude-transcripts' "retro labels the harness its signals come from"
assert_contains "$RS" $'RETRO-PLAN\t1\t1' "a session that opened plan mode is counted"
assert_contains "$RS" $'RETRO-CORRECTION\t2' "user redirects (no…/actually…) counted as corrections"

# ── git ship/peak (repo scope, real git repo) ──
gitrepo="$sb/gitrepo"; mkdir -p "$gitrepo"
( cd "$gitrepo" && git init -q && git config user.email t@t.t && git config user.name t \
  && echo a > f && git add f && git commit -qm c1 \
  && printf 'a\nbb\n' > f && git add f && git commit -qm c2 ) >/dev/null 2>&1
gkey="$(printf '%s' "$gitrepo" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$sb/.claude/projects/$gkey"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"x"}}' > "$sb/.claude/projects/$gkey/s.jsonl"
GS="$(HOME="$sb" "$AU" retro --repo "$gitrepo")"
assert_contains "$GS" $'RETRO-SHIP\t2\t' "RETRO-SHIP reports commit count + LOC from git over the window"
assert_contains "$GS" "RETRO-PEAK" "RETRO-PEAK reports the busiest day"

t_done
