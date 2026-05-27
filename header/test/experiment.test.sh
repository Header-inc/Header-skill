#!/usr/bin/env bash
# test/experiment.test.sh — unit tests for bin/header-experiment.
#
# Strategy: never invoke a real `claude`. Use HEADER_EXPERIMENT_ADAPTER to
# point at a tiny bash stub that emits deterministic JSON usage. That covers
# the runner's parsing + analyse's stats end-to-end without spending tokens
# or needing network.
#
# HEADER_HOME is pinned to a sandbox so experiment state doesn't touch ~/.header.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

HE="$SKILL_DIR/bin/header-experiment"
sb="$(make_sandbox)"
EXP() { HEADER_HOME="$sb/.header" "$HE" "$@"; }

# ── helpers ──────────────────────────────────────────────────
exp_dir_for() { printf '%s/.header/experiments/%s' "$sb" "$1"; }

# write_stub_adapter — make a stub that prints fake usage per arm. By default
# arm A is "expensive + always succeeds", arm B is "cheap + always succeeds".
# Optional second arg makes B fail on one task (to exercise non-inferiority).
write_stub_adapter() {
  local path="$1"; local b_fails_task="${2:-}"
  cat > "$path" <<EOF
#!/usr/bin/env bash
# Stub: task_id arm rep prompt_file
task="\$1"; arm="\$2"; rep="\$3"
case "\$arm" in
  A*) cost="0.10"; tokens=1000 ;;
  B*) cost="0.06"; tokens=600 ;;
  *)  cost="0.08"; tokens=800 ;;
esac
printf '{"type":"result","model":"stub-%s","total_cost_usd":%s,"usage":{"input_tokens":%d,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}\n' \\
  "\$arm" "\$cost" "\$tokens"
# Optional: B fails on the listed task to exercise non-inferiority.
if [ "\$arm" = "B" ] && [ "\$task" = "$b_fails_task" ]; then
  exit 1
fi
exit 0
EOF
  chmod +x "$path"
}

# write_task_prompt — drop a tiny prompt file under the experiment dir.
write_task_prompt() {
  local exp="$1" tid="$2"
  local d; d="$(exp_dir_for "$exp")/tasks"
  mkdir -p "$d"
  echo "prompt for $tid" > "$d/$tid.md"
}

# ── usage + dispatcher ───────────────────────────────────────
EXP >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "no subcommand → exit 1"
EXP bogus >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "unknown subcommand → exit 1"

# ── define: scaffolds a spec with sane defaults ──────────────
EXP define exp-1 --description "first" --arm "A=claude-opus-4-7" --arm "B=claude-sonnet-4-6" --replicates 2 >/dev/null
assert_eq "yes" "$([ -f "$(exp_dir_for exp-1)/spec" ] && echo yes || echo no)" \
  "define wrote spec file"
spec_content="$(cat "$(exp_dir_for exp-1)/spec")"
assert_contains "$spec_content" "id: exp-1"        "spec carries the id"
assert_contains "$spec_content" "description: first" "spec carries description"
assert_contains "$spec_content" "[arm:A]"          "spec has [arm:A] section"
assert_contains "$spec_content" "[arm:B]"          "spec has [arm:B] section"
assert_contains "$spec_content" "model: claude-opus-4-7"   "spec carries arm A model"
assert_contains "$spec_content" "model: claude-sonnet-4-6" "spec carries arm B model"
assert_contains "$spec_content" "replicates: 2"    "spec carries replicates override"
assert_contains "$spec_content" "non_inferiority_margin:" "spec carries margin default"
assert_contains "$spec_content" "[task:example]"   "spec scaffolds a placeholder task"

# refuse duplicate id
EXP define exp-1 >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "define with existing id → exit 1 (no clobber)"

# bad id (path separator) is rejected
EXP define "../bad" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "define rejects unsafe id ('../bad')"

# id is required
EXP define >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "define without <id> → exit 1"

# ── validate: catches missing prompts, bad replicates ────────
EXP validate exp-1 >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "validate fails when prompt file doesn't exist"
# Now create the prompt file → validation passes
write_task_prompt exp-1 example
EXP validate exp-1 >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "validate passes once the prompt file exists"
assert_contains "$(EXP validate exp-1 2>&1)" "2 arm(s), 1 task(s)" \
  "validate reports arm + task counts"

# bad replicates value → reject
sed -i 's/^replicates: 2/replicates: zero/' "$(exp_dir_for exp-1)/spec"
EXP validate exp-1 >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "validate rejects non-integer replicates"
sed -i 's/^replicates: zero/replicates: 2/' "$(exp_dir_for exp-1)/spec"

# one arm only → reject
EXP define exp-1arm --arm "A=opus" >/dev/null
write_task_prompt exp-1arm example
EXP validate exp-1arm >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "validate rejects experiments with <2 arms"

# ── run: end-to-end with the stub adapter ────────────────────
write_stub_adapter "$sb/adapter.sh"
# Use the exp-1 spec; point repo at a tmp git repo so worktrees work.
git_repo="$sb/repo"
mkdir -p "$git_repo" && (cd "$git_repo" && git init -q && \
  git config user.email t@t && git config user.name t && \
  echo hi > a.txt && git add a.txt && git commit -qm init)
# update spec to use the git repo + a NO-OP verifier (true).
sed -i "s|^repo: .|repo: $git_repo|" "$(exp_dir_for exp-1)/spec"

EXP run exp-1 --yes --adapter "$sb/adapter.sh" >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "run exits 0 with stub adapter"
runs_file="$(exp_dir_for exp-1)/runs.jsonl"
assert_eq "yes" "$([ -s "$runs_file" ] && echo yes || echo no)" "run produced runs.jsonl"
n_lines="$(wc -l < "$runs_file" | tr -d ' ')"
# 2 arms × 1 task × 2 replicates = 4
assert_eq "4" "$n_lines" "runs.jsonl has 4 records (2 arms × 1 task × 2 reps)"
assert_contains "$(cat "$runs_file")" '"arm":"A"' "runs.jsonl includes arm A"
assert_contains "$(cat "$runs_file")" '"arm":"B"' "runs.jsonl includes arm B"
assert_contains "$(cat "$runs_file")" '"cost_usd":0.100000' "arm A cost parsed from adapter JSON"
assert_contains "$(cat "$runs_file")" '"cost_usd":0.060000' "arm B cost parsed from adapter JSON"
assert_contains "$(cat "$runs_file")" '"input_tokens":1000' "arm A input tokens parsed"
assert_contains "$(cat "$runs_file")" '"input_tokens":600'  "arm B input tokens parsed"
assert_contains "$(cat "$runs_file")" '"success":true'      "verify exit 0 → success=true"

# ── run --aa: writes runs-aa.jsonl, both slots use first arm's config ──
EXP run exp-1 --aa --yes --adapter "$sb/adapter.sh" >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "run --aa exits 0"
aa_runs="$(exp_dir_for exp-1)/runs-aa.jsonl"
assert_eq "yes" "$([ -s "$aa_runs" ] && echo yes || echo no)" "run --aa produced runs-aa.jsonl"
assert_contains "$(cat "$aa_runs")" '"arm":"A"' "A/A: slot 1 labelled A"
assert_contains "$(cat "$aa_runs")" '"arm":"A_2"' "A/A: slot 2 labelled A_2 (same config as A)"
# the model captured for A_2 should be the arm-A model from the adapter
assert_not_contains "$(cat "$aa_runs")" '"model":"stub-B"' "A/A: never uses arm B's config"

# ── run: refuses missing claude when no adapter set ──────────
# (Only check this when claude is genuinely absent; in CI it may be installed.)
if ! command -v claude >/dev/null 2>&1; then
  EXP run exp-1 --yes >/dev/null 2>&1; rc=$?
  assert_exit 1 "$rc" "run without adapter → exit 1 when 'claude' is not on PATH"
fi

# ── run: cost gate refuses cleanly when no TTY + no --yes ────
# Regression: an earlier version tried to read /dev/tty here. In agent
# subshells /dev/tty exists but open() returns ENXIO (no controlling
# terminal). The fix is to detect no-TTY with `[ -t 0 ]` and exit with a
# helpful error pointing at --yes — NOT to error out via bash's "No such
# device or address" redirect failure.
no_tty_out="$(EXP run exp-1 </dev/null 2>&1)"; rc=$?
assert_exit 1 "$rc" "run without --yes + no TTY → exit 1 (cleanly)"
assert_not_contains "$no_tty_out" "No such device" \
  "no-TTY refusal does NOT leak the /dev/tty 'No such device' error"
assert_contains "$no_tty_out" "no TTY for confirmation" \
  "no-TTY refusal explains the missing TTY"
assert_contains "$no_tty_out" "--yes" \
  "no-TTY refusal points at --yes so callers know how to authorize"

# ── run: cost gate speaks BOTH billing modes (API + subscription headroom)
# Regression after the 2026-05-27 audit where the gate only mentioned dollars,
# misleading users on a Max subscription (no $ per token, just usage-limit
# headroom). header-cost already had the framing; we just hadn't pulled it
# into header-experiment's gate.
gate_out="$(EXP run exp-1 </dev/null 2>&1)"
assert_contains "$gate_out" "API / Console (pay-per-token)" \
  "cost gate mentions API/Console billing basis"
assert_contains "$gate_out" "Claude subscription" \
  "cost gate mentions subscription basis (Pro / Max)"
assert_contains "$gate_out" "usage-limit headroom" \
  "cost gate flags that subscription users spend headroom, not dollars"
# The load-bearing rule appears in the gate itself.
assert_contains "$gate_out" '$60 experiment to prove a $0.10 effect' \
  "cost gate quotes the load-bearing rule verbatim"
# Both levers — magnitude AND experiment-cost — surface for the user.
assert_contains "$gate_out" "Levers to make an experiment cheaper" \
  "cost gate surfaces the cheap-experiment levers"
assert_contains "$gate_out" "Haiku" \
  "cost gate mentions Haiku as a cheap-adapter lever"
assert_contains "$gate_out" "k 1" \
  "cost gate mentions --k 1 as a sanity-only lever"

# ── analyze: bootstrap CI, paired-by-task ────────────────────
# Hand-author a noisy 5-task runs.jsonl: B is reliably cheaper everywhere,
# success holds across the board. Verdict should be "B wins".
EXP define exp-stat --arm "A=opus" --arm "B=sonnet" --replicates 3 >/dev/null
write_task_prompt exp-stat example
sed -i "s|^repo: .|repo: $git_repo|" "$(exp_dir_for exp-stat)/spec"
five_tasks_runs() {
  local tid c_a c_b s_a s_b
  for tid in t1 t2 t3 t4 t5; do
    case "$tid" in
      t1) c_a=0.10; c_b=0.06 ;;
      t2) c_a=0.20; c_b=0.12 ;;
      t3) c_a=0.15; c_b=0.09 ;;
      t4) c_a=0.25; c_b=0.15 ;;
      t5) c_a=0.30; c_b=0.18 ;;
    esac
    for r in 0 1 2; do
      printf '{"task":"%s","arm":"A","rep":%d,"cost_usd":%s,"success":true}\n' "$tid" "$r" "$c_a"
      printf '{"task":"%s","arm":"B","rep":%d,"cost_usd":%s,"success":true}\n' "$tid" "$r" "$c_b"
    done
  done
}
five_tasks_runs > "$(exp_dir_for exp-stat)/runs.jsonl"

EXP analyze exp-stat --seed 7 --bootstrap 500 >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "analyze on 5 tasks exits 0"
result="$(cat "$(exp_dir_for exp-stat)/result.json")"
assert_contains "$result" '"tasks_paired": 5'        "analyze pairs 5 tasks"
assert_contains "$result" '"mode": "ab"'             "analyze tags mode ab"
assert_contains "$result" '"favorable": true'        "cost CI < 0 → favorable=true"
assert_contains "$result" '"non_inferior": true'     "success holds → non_inferior=true"
assert_contains "$result" '"verdict": "B wins'       "verdict: B wins"
assert_contains "$result" '"bootstrap_iters": 500'   "bootstrap iter count carried"
# determinism: same seed, same CI
EXP analyze exp-stat --seed 7 --bootstrap 500 >/dev/null
r2="$(cat "$(exp_dir_for exp-stat)/result.json")"
assert_eq "$result" "$r2" "analyze is deterministic for a fixed seed"

# ── analyze: success regression → no proven win ──────────────
# Same noisy 5-task data but B fails one task entirely. Success diff CI should
# fall below −δ=0.02, blocking the merge even with cost wins.
{
  five_tasks_runs | awk '
    BEGIN{ FS=OFS="" }
    /"arm":"B"/ && /"task":"t5"/ { sub(/"success":true/, "\"success\":false") } { print }'
} > "$(exp_dir_for exp-stat)/runs.jsonl"
EXP analyze exp-stat --seed 7 --bootstrap 500 >/dev/null
result2="$(cat "$(exp_dir_for exp-stat)/result.json")"
assert_contains "$result2" '"favorable": true'      "cost still favourable when B fails one task"
assert_contains "$result2" '"non_inferior": false'  "success non-inferiority fails when B regresses"
assert_contains "$result2" '"verdict": "no proven win"' "blocked by non-inferiority → no proven win"
assert_contains "$result2" "success regressed beyond" "verdict reason mentions success regression"

# ── analyze: underpowered (<5 tasks) → flagged ──────────────
# One-task analysis collapses CI; verdict must flag the lack of power, not
# pretend significance.
EXP define exp-tiny --arm "A=opus" --arm "B=sonnet" >/dev/null
write_task_prompt exp-tiny example
{
  printf '{"task":"t1","arm":"A","rep":0,"cost_usd":0.10,"success":true}\n'
  printf '{"task":"t1","arm":"B","rep":0,"cost_usd":0.06,"success":true}\n'
} > "$(exp_dir_for exp-tiny)/runs.jsonl"
EXP analyze exp-tiny >/dev/null
assert_contains "$(cat "$(exp_dir_for exp-tiny)/result.json")" '"verdict": "underpowered"' \
  "1-task experiment → verdict underpowered (never \"B wins\")"

# ── analyze --aa: harness validator ──────────────────────────
EXP define exp-aa --arm "A=opus" --arm "B=sonnet" >/dev/null
write_task_prompt exp-aa example
{
  # diffs around 0 — clean harness
  for tid in t1 t2 t3 t4 t5; do
    base="0.10"
    for r in 0 1; do
      printf '{"task":"%s","arm":"A","rep":%d,"cost_usd":%s,"success":true}\n'   "$tid" "$r" "$base"
      printf '{"task":"%s","arm":"A_2","rep":%d,"cost_usd":%s,"success":true}\n' "$tid" "$r" "$base"
    done
  done
} > "$(exp_dir_for exp-aa)/runs-aa.jsonl"
EXP analyze exp-aa --aa >/dev/null
aa_result="$(cat "$(exp_dir_for exp-aa)/result-aa.json")"
assert_contains "$aa_result" '"mode": "aa"'         "analyze --aa tags mode aa"
assert_contains "$aa_result" '"verdict": "A/A OK'   "clean A/A → 'A/A OK' verdict"

# ── analyze --aa: biased harness flagged ─────────────────────
# Inject a systematic bias: arm A is always cheaper than arm A_2 (e.g. cache
# warmup hits the second slot). CI should NOT contain 0 → flagged.
{
  for tid in t1 t2 t3 t4 t5; do
    for r in 0 1; do
      printf '{"task":"%s","arm":"A","rep":%d,"cost_usd":0.10,"success":true}\n'   "$tid" "$r"
      printf '{"task":"%s","arm":"A_2","rep":%d,"cost_usd":0.30,"success":true}\n' "$tid" "$r"
    done
  done
} > "$(exp_dir_for exp-aa)/runs-aa.jsonl"
EXP analyze exp-aa --aa >/dev/null
aa_biased="$(cat "$(exp_dir_for exp-aa)/result-aa.json")"
assert_contains "$aa_biased" '"verdict": "A/A BIASED' \
  "biased A/A (CI excludes 0) → flagged 'A/A BIASED'"

# ── report: pretty output for an A/B result ──────────────────
five_tasks_runs > "$(exp_dir_for exp-stat)/runs.jsonl"
EXP analyze exp-stat --seed 7 >/dev/null
rep_out="$(EXP report exp-stat 2>&1)"
assert_contains "$rep_out" "header-experiment is BETA" "report prints the beta banner"
assert_contains "$rep_out" "A vs B"                    "report header: A vs B"
assert_contains "$rep_out" "B − A"                     "report shows the diff label"
assert_contains "$rep_out" "95% CI"                    "report shows CI"
assert_contains "$rep_out" "Conservative savings rate" "report shows the conservative savings rate"

# report --aa
EXP report exp-aa --aa 2>&1 >/dev/null
rep_aa="$(EXP report exp-aa --aa 2>&1)"
assert_contains "$rep_aa" "A/A (noise floor)" "report --aa header"
assert_contains "$rep_aa" "A/A interpretation" "report --aa explains the verdict"

# ── report needs a result.json ──────────────────────────────
EXP define exp-noresult --arm "A=opus" --arm "B=sonnet" >/dev/null
EXP report exp-noresult >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "report fails when result.json doesn't exist yet"

# ── run: cost-gate prompts when no --yes and no adapter ──────
# We can't easily exercise the TTY prompt in tests; ensure that with --yes the
# gate is skipped and the run proceeds, AND that --adapter also implicitly
# skips it (so test runs don't hang).
EXP run exp-1 --yes --adapter "$sb/adapter.sh" --k 1 >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "run with --yes + --adapter proceeds without prompting"

# ── adapter exit-code propagates to success ──────────────────
# Stub that always exits 1 → success=false (the agent itself "failed").
# (Tier-1 oracle is the verify step, but a failing agent also flips success.)
cat > "$sb/fail-adapter.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"type":"result","model":"stub","total_cost_usd":0.05,"usage":{"input_tokens":100,"output_tokens":10}}\n'
exit 0
EOF
chmod +x "$sb/fail-adapter.sh"
# Use a verify cmd that fails ("false") to drive success=false.
sed -i 's/^verify: true$/verify: false/' "$(exp_dir_for exp-1)/spec"
EXP run exp-1 --yes --adapter "$sb/fail-adapter.sh" --k 1 >/dev/null 2>&1
assert_contains "$(cat "$(exp_dir_for exp-1)/runs.jsonl")" '"success":false' \
  "verify exit != 0 → success=false in runs.jsonl"

# ── new (audit-aware wizard / one-shot) ──────────────────────
# Pre-build a small git repo so --kind prompt-debt-deletion has a real file
# to strip lines from, and --repo can resolve.
nw_repo="$sb/nw-repo"
mkdir -p "$nw_repo" && (cd "$nw_repo" && git init -q && \
  git config user.email t@t && git config user.name t)
cat > "$nw_repo/CLAUDE.md" <<'EOF'
# Project rules
You are an expert engineer.
Always think step by step.
Take a deep breath.
Don't hallucinate.
Be helpful.
EOF
echo '{"name":"x"}' > "$nw_repo/package.json"
(cd "$nw_repo" && git add . && git commit -qm init)

# 1) generic mode (--arm/--task/--verify) writes a complete, valid spec
EXP new gen-1 --arm "A:claude-opus-4-7" --arm "B:claude-sonnet-4-6" \
  --task "Refactor a function — keep tests green." \
  --verify "true" --replicates 2 --description "model swap (generic)" \
  --repo "$nw_repo" >/dev/null
assert_eq "yes" "$([ -f "$(exp_dir_for gen-1)/spec" ] && echo yes || echo no)" \
  "new (generic) wrote a spec"
spec_gen="$(cat "$(exp_dir_for gen-1)/spec")"
assert_contains "$spec_gen" "model: claude-opus-4-7"   "generic spec: arm A model"
assert_contains "$spec_gen" "model: claude-sonnet-4-6" "generic spec: arm B model"
assert_contains "$spec_gen" "description: model swap (generic)" "generic spec: description"
assert_contains "$spec_gen" "repo: $nw_repo"           "generic spec: repo absolute"
# Inline task → file written under exp_dir/tasks/
assert_eq "yes" "$([ -f "$(exp_dir_for gen-1)/tasks/t1.md" ] && echo yes || echo no)" \
  "inline task is written to <exp_dir>/tasks/t1.md"
# validate is implicit: `new` calls it; if validate fails the command errors
EXP new gen-1 --arm A: --arm B: --task t --verify true --repo "$nw_repo" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "new refuses duplicate id (no clobber)"

# 2) --kind prompt-debt-deletion auto-generates arm B's overrides_dir
EXP new debt-1 --kind prompt-debt-deletion \
  --file CLAUDE.md --lines "3,4,5" \
  --task "Tiny task — exit cleanly." --verify "true" \
  --replicates 2 --ledger-key delete-cargo-cult \
  --repo "$nw_repo" >/dev/null
assert_eq "yes" "$([ -f "$(exp_dir_for debt-1)/spec" ] && echo yes || echo no)" \
  "new --kind prompt-debt-deletion wrote a spec"
spec_debt="$(cat "$(exp_dir_for debt-1)/spec")"
# ledger_key must be in the TOP block (before [section]s) so spec_get_scalar finds it
assert_contains "$spec_debt" "ledger_key: delete-cargo-cult" "ledger_key written into spec"
ledger_line="$(awk '/ledger_key/{print NR;exit}' "$(exp_dir_for debt-1)/spec")"
first_section_line="$(awk '/^\[/{print NR;exit}' "$(exp_dir_for debt-1)/spec")"
[ "${ledger_line:-9999}" -lt "${first_section_line:-9999}" ] && lk_in_top=yes || lk_in_top=no
assert_eq "yes" "$lk_in_top" "ledger_key is in the top-level block (above first [section])"
assert_contains "$spec_debt" "overrides_dir: arms/B" "arm B has overrides_dir = arms/B"
# Arm B's CLAUDE.md exists and has lines 3,4,5 removed
arm_b_file="$(exp_dir_for debt-1)/arms/B/CLAUDE.md"
assert_eq "yes" "$([ -f "$arm_b_file" ] && echo yes || echo no)" \
  "arm B's CLAUDE.md materialized under arms/B/"
arm_b_lines="$(wc -l < "$arm_b_file" | tr -d ' ')"
assert_eq "3" "$arm_b_lines" "arm B's CLAUDE.md has 3 lines (original 6 − 3 stripped)"
assert_not_contains "$(cat "$arm_b_file")" "think step by step" "stripped line 3 (cargo-cult)"
assert_not_contains "$(cat "$arm_b_file")" "deep breath"         "stripped line 4 (cargo-cult)"
assert_not_contains "$(cat "$arm_b_file")" "hallucinate"         "stripped line 5 (cargo-cult)"
# Bad --lines (non-integer) → refused
EXP new debt-bad --kind prompt-debt-deletion --file CLAUDE.md --lines "abc" \
  --task t --verify true --repo "$nw_repo" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "new --kind prompt-debt-deletion rejects non-integer --lines"
# Missing file (audit pointed at nonsense) → refused
EXP new debt-nofile --kind prompt-debt-deletion --file does-not-exist.md --lines "1" \
  --task t --verify true --repo "$nw_repo" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "new --kind prompt-debt-deletion rejects missing --file"

# 3) --kind model-swap → two arms differ only in model
EXP new swap-1 --kind model-swap --from claude-opus-4-7 --to claude-sonnet-4-6 \
  --task "Tiny." --verify "true" --replicates 2 --repo "$nw_repo" >/dev/null
spec_swap="$(cat "$(exp_dir_for swap-1)/spec")"
assert_contains "$spec_swap" "model: claude-opus-4-7"   "swap spec: arm A model"
assert_contains "$spec_swap" "model: claude-sonnet-4-6" "swap spec: arm B model"
# Neither arm has overrides_dir (it's a model swap, not a file change)
assert_not_contains "$spec_swap" "overrides_dir: arms" "swap spec: no overrides_dir for either arm"

# 4) Unknown --kind → refused
EXP new bad-kind --kind not-a-kind --repo "$nw_repo" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "new rejects unknown --kind"

# 5) Task passed as a real repo-relative file path → stored as relative
mkdir -p "$nw_repo/tasks"
echo "Real prompt." > "$nw_repo/tasks/real.md"
EXP new path-1 --arm A: --arm B: --task "tasks/real.md" --verify true \
  --replicates 1 --repo "$nw_repo" >/dev/null
spec_path="$(cat "$(exp_dir_for path-1)/spec")"
assert_contains "$spec_path" "prompt: tasks/real.md" \
  "repo-relative task path is stored as relative (not absolute)"
EXP validate path-1 >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "validate finds the repo-relative task file"
# A path-resolution sanity check: a task path that doesn't exist anywhere is
# treated as inline (file written under exp_dir/tasks/). NOT a fatal error.
EXP new path-inline --arm A: --arm B: --task "Just refactor X." --verify true \
  --replicates 1 --repo "$nw_repo" >/dev/null
assert_eq "yes" "$([ -f "$(exp_dir_for path-inline)/tasks/t1.md" ] && echo yes || echo no)" \
  "non-path --task value is written to <exp_dir>/tasks/t1.md as an inline prompt"

# 6) Magnitude estimate fires for --kind prompt-debt-deletion (v0.12.0)
# Need a bigger CLAUDE.md so a 1-line delete is reliably <5%. Build one.
big_repo="$sb/big-repo"
mkdir -p "$big_repo" && (cd "$big_repo" && git init -q && \
  git config user.email t@t && git config user.name t)
{
  printf '# Project rules\n'
  printf 'You are an expert engineer.\n'
  printf 'Always think step by step.\n'
  for i in $(seq 1 50); do
    printf 'Actual content line %d with real instructions and useful context here.\n' "$i"
  done
} > "$big_repo/CLAUDE.md"
(cd "$big_repo" && git add . && git commit -qm init)

mag_small_out="$(EXP new mag-small --kind prompt-debt-deletion \
  --file CLAUDE.md --lines "3" --task t --verify true \
  --replicates 2 --repo "$big_repo" 2>&1)"
assert_contains "$mag_small_out" "Magnitude estimate" "magnitude estimate prints"
assert_contains "$mag_small_out" "of the file"        "magnitude estimate shows % of file"
assert_contains "$mag_small_out" '$60 experiment to prove a $0.10 effect' \
  "magnitude estimate quotes the load-bearing rule"
assert_contains "$mag_small_out" "<5% of the file"    "small change triggers the <5% pointer"
assert_contains "$mag_small_out" "[Apply with review]" \
  "small-magnitude estimate surfaces the [Apply with review] path"
assert_contains "$mag_small_out" "Haiku"              "small-magnitude estimate surfaces the cheap-experiment Haiku lever"
assert_contains "$mag_small_out" "narrow"             "small-magnitude estimate surfaces the narrow-verify lever"

# 6b) Big change → no [Apply with review] suggestion (magnitude is enough)
big_repo2="$sb/big-repo2"
mkdir -p "$big_repo2" && (cd "$big_repo2" && git init -q && \
  git config user.email t@t && git config user.name t)
{ printf 'line1\nline2\nline3\nline4\nline5\n'; } > "$big_repo2/CLAUDE.md"
(cd "$big_repo2" && git add . && git commit -qm init)
mag_big_out="$(EXP new mag-big --kind prompt-debt-deletion \
  --file CLAUDE.md --lines "1,2,3" --task t --verify true \
  --replicates 2 --repo "$big_repo2" 2>&1)"
assert_contains     "$mag_big_out" "Magnitude estimate" "magnitude estimate prints for big changes too"
assert_not_contains "$mag_big_out" "<5% of the file"   "big-change estimate does NOT trigger the <5% pointer"

# 7) --kind clause-add (insertion experiments)
EXP new clause-1 --kind clause-add \
  --file CLAUDE.md --after-line 1 \
  --text "For model-field changes, invoke the model-field-checklist skill first." \
  --task "tiny" --verify true --replicates 2 --repo "$big_repo" >/dev/null
clause_spec="$(cat "$(exp_dir_for clause-1)/spec")"
assert_contains "$clause_spec" "overrides_dir: arms/B" \
  "clause-add spec: arm B has overrides_dir = arms/B"
arm_b_file="$(exp_dir_for clause-1)/arms/B/CLAUDE.md"
assert_eq "yes" "$([ -f "$arm_b_file" ] && echo yes || echo no)" \
  "clause-add arm B's file materialized"
assert_contains "$(cat "$arm_b_file")" "model-field-checklist skill" \
  "clause-add inserted the new instruction"
# Original file has 53 lines (header + 50 generated); arm B should have 54
orig_lines="$(wc -l < "$big_repo/CLAUDE.md" | tr -d ' ')"
new_lines="$(wc -l < "$arm_b_file" | tr -d ' ')"
assert_eq "$(( orig_lines + 1 ))" "$new_lines" \
  "clause-add added exactly one line"
# Insertion happens AFTER line 1 — line 1 should still be the original header
head1="$(head -1 "$arm_b_file")"
assert_eq "# Project rules" "$head1" "clause-add preserved the existing line 1"
head2="$(sed -n '2p' "$arm_b_file")"
assert_contains "$head2" "model-field-checklist skill" \
  "clause-add inserted at position 2 (after line 1)"

# 7b) clause-add at after-line=0 inserts at the top
EXP new clause-top --kind clause-add \
  --file CLAUDE.md --after-line 0 \
  --text "TOP_LINE_INSERTED" \
  --task "tiny" --verify true --replicates 2 --repo "$big_repo" >/dev/null
top_file="$(exp_dir_for clause-top)/arms/B/CLAUDE.md"
assert_eq "TOP_LINE_INSERTED" "$(head -1 "$top_file")" \
  "clause-add --after-line 0 inserts at the very top of the file"

# 7c) clause-add via --text-file (multi-line content)
multi_file="$sb/multi.txt"
{ printf 'Line A\n'; printf 'Line B\n'; printf 'Line C\n'; } > "$multi_file"
EXP new clause-multi --kind clause-add \
  --file CLAUDE.md --after-line 1 --text-file "$multi_file" \
  --task "tiny" --verify true --replicates 2 --repo "$big_repo" >/dev/null
multi_b="$(exp_dir_for clause-multi)/arms/B/CLAUDE.md"
assert_contains "$(cat "$multi_b")" "Line A" "clause-add --text-file: multi-line content present"
assert_contains "$(cat "$multi_b")" "Line B" "clause-add --text-file: line B present"
assert_contains "$(cat "$multi_b")" "Line C" "clause-add --text-file: line C present"

# 7d) clause-add validates inputs
EXP new clause-badline --kind clause-add --file CLAUDE.md \
  --after-line "abc" --text "x" --task t --verify true \
  --repo "$big_repo" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "clause-add rejects non-integer --after-line"
EXP new clause-nofile --kind clause-add --file does-not-exist.md \
  --after-line 0 --text "x" --task t --verify true \
  --repo "$big_repo" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "clause-add rejects missing --file"
EXP new clause-notext --kind clause-add --file CLAUDE.md \
  --after-line 0 --task t --verify true \
  --repo "$big_repo" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "clause-add requires --text or --text-file"

# ── merge ─────────────────────────────────────────────────────
# Synthesize a B-wins runs.jsonl for the prompt-debt experiment, analyze, merge.
synth_runs() {
  # 5 tasks × 2 replicates × 2 arms, B reliably cheaper
  local exp="$1"
  local out; out="$(exp_dir_for "$exp")/runs.jsonl"
  : > "$out"
  local tid c_a c_b r
  for tid in t1 t2 t3 t4 t5; do
    case "$tid" in
      t1) c_a=0.20; c_b=0.12 ;;
      t2) c_a=0.30; c_b=0.18 ;;
      t3) c_a=0.40; c_b=0.24 ;;
      t4) c_a=0.50; c_b=0.30 ;;
      t5) c_a=0.60; c_b=0.36 ;;
    esac
    for r in 0 1; do
      printf '{"task":"%s","arm":"A","rep":%d,"cost_usd":%s,"success":true}\n' "$tid" "$r" "$c_a" >> "$out"
      printf '{"task":"%s","arm":"B","rep":%d,"cost_usd":%s,"success":true}\n' "$tid" "$r" "$c_b" >> "$out"
    done
  done
}

# Re-create CLAUDE.md (an earlier test may have shifted the repo state)
cat > "$nw_repo/CLAUDE.md" <<'EOF'
# Project rules
You are an expert engineer.
Always think step by step.
Take a deep breath.
Don't hallucinate.
Be helpful.
EOF

synth_runs debt-1
EXP analyze debt-1 --seed 7 >/dev/null
# B-wins applies; CLAUDE.md in the repo gets the lines stripped
EXP merge debt-1 --yes >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "merge on B-wins exits 0"
assert_not_contains "$(cat "$nw_repo/CLAUDE.md")" "think step by step" \
  "merge stripped the cargo-cult line from the repo's CLAUDE.md"
assert_not_contains "$(cat "$nw_repo/CLAUDE.md")" "deep breath" \
  "merge stripped 'deep breath' from the repo's CLAUDE.md"
assert_contains "$(cat "$nw_repo/CLAUDE.md")" "You are an expert engineer." \
  "merge preserved the lines that weren't in the deletion list"

# Header-Audit-Finding trailer suggestion appears (provenance for the commit)
merge_out="$(EXP merge debt-1 --yes 2>&1)"
assert_contains "$merge_out" "Header-Audit-Finding: delete-cargo-cult" \
  "merge prints the Header-Audit-Finding trailer suggestion when ledger_key is set"
assert_contains "$merge_out" "header-ledger record applied" \
  "merge prints the ledger record command"

# No-proven-win → refuses (without --force)
synth_flat_runs() {
  local out; out="$(exp_dir_for "$1")/runs.jsonl"
  : > "$out"
  local tid r
  for tid in t1 t2 t3 t4 t5; do for r in 0 1; do
    printf '{"task":"%s","arm":"A","rep":%d,"cost_usd":0.50,"success":true}\n' "$tid" "$r" >> "$out"
    printf '{"task":"%s","arm":"B","rep":%d,"cost_usd":0.51,"success":true}\n' "$tid" "$r" >> "$out"
  done; done
}
EXP new flat-1 --kind prompt-debt-deletion --file CLAUDE.md --lines "6" \
  --task "tiny" --verify true --replicates 2 --repo "$nw_repo" >/dev/null
synth_flat_runs flat-1
EXP analyze flat-1 --seed 7 >/dev/null
EXP merge flat-1 --yes >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "merge refuses when verdict is not 'B wins'"
refuse_out="$(EXP merge flat-1 --yes 2>&1)"
assert_contains "$refuse_out" "refusing to merge" "merge refusal mentions 'refusing to merge'"
# --force overrides the refusal
EXP merge flat-1 --yes --force >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "merge --force overrides the verdict refusal"

# A/A result → refuses (model-swap or otherwise; the spec is the same)
EXP new aa-m --arm A: --arm B: --task "tiny" --verify true \
  --replicates 1 --repo "$nw_repo" >/dev/null
mkdir -p "$(exp_dir_for aa-m)"
cat > "$(exp_dir_for aa-m)/result.json" << 'EOF'
{ "mode": "aa", "arms": ["A","A_2"], "verdict": "A/A OK — harness clean" }
EOF
EXP merge aa-m --yes >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "merge refuses an A/A result (nothing to merge)"

# Missing result.json → error
EXP new noresult --arm A: --arm B: --task t --verify true \
  --replicates 1 --repo "$nw_repo" >/dev/null
EXP merge noresult --yes >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "merge errors when result.json is missing"

# Model-swap merge: no files to copy, prints model-update note + ledger hint
EXP new swap-merge --kind model-swap --from claude-opus-4-7 --to claude-sonnet-4-6 \
  --task "tiny" --verify true --replicates 2 \
  --ledger-key route-boilerplate --repo "$nw_repo" >/dev/null
synth_runs swap-merge
EXP analyze swap-merge --seed 7 >/dev/null
swap_merge_out="$(EXP merge swap-merge --yes 2>&1)"
assert_contains "$swap_merge_out" "model swap, not a code change" \
  "merge on a model-swap spec explains there are no files to copy"
assert_contains "$swap_merge_out" "Update your default to 'claude-sonnet-4-6'" \
  "merge on a model-swap surfaces the target model"
assert_contains "$swap_merge_out" "header-ledger record applied \"route-boilerplate\"" \
  "merge on a model-swap still suggests the ledger record"

t_done
