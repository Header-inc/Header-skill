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

t_done
