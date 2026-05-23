#!/usr/bin/env bash
# test/cost.test.sh — unit tests for bin/header-cost (the realized-savings meter).
# HEADER_HOME is pinned to a sandbox so the price-override file never touches the
# real ~/.header.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

HC="$SKILL_DIR/bin/header-cost"
sb="$(make_sandbox)"
COST() { HEADER_HOME="$sb" "$HC" "$@"; }

# ── cost primitive: exact arithmetic (USD per 1M tokens) ──────
assert_eq "90.000000" "$(COST cost claude-opus-4-7 1000000 1000000)" \
  "opus 1M in + 1M out = 15 + 75 = 90"
assert_eq "1.500000"  "$(COST cost opus 0 0 1000000 0)" \
  "opus 1M cache_read = 1.50"
assert_eq "18.750000" "$(COST cost opus 0 0 0 1000000)" \
  "opus 1M cache_write = 18.75"
assert_eq "13.500000" "$(COST cost claude-sonnet-4-6 2000000 500000)" \
  "sonnet 2M in + 0.5M out = 6 + 7.5 = 13.50"
assert_eq "6.000000"  "$(COST cost claude-haiku-4-5 1000000 1000000)" \
  "haiku 1M in + 1M out = 1 + 5 = 6"

# ── family matching is robust to version/name churn ───────────
assert_eq "90.000000" "$(COST cost claude-3-opus 1000000 1000000)" \
  "old name 'claude-3-opus' still resolves to the opus family"
assert_eq "$(COST cost claude-opus-4-7 1000000 1000000)" "$(COST cost OPUS 1000000 1000000)" \
  "family match is case-insensitive"

# ── unknown model → exit 2, prints 0, warns on stderr ─────────
out="$(COST cost gpt-4o 1000 1000 2>/dev/null)"; rc=$?
assert_exit 2 "$rc" "unknown model → exit 2"
assert_eq "0.000000" "$out" "unknown model prints 0 cost"
assert_contains "$(COST cost gpt-4o 1000 1000 2>&1 >/dev/null)" "unknown model" \
  "unknown model warns on stderr"

# ── price overrides (family + exact id; comments/blanks ignored) ─
printf '# negotiated\nopus 10 50 1.00 12.50\n\nclaude-sonnet-4-6 2 8 0.20 2.50\n' > "$sb/prices.tsv"
assert_eq "60.000000" "$(COST cost opus 1000000 1000000)" \
  "family override: opus now 10 + 50 = 60"
assert_eq "10.000000" "$(COST cost claude-sonnet-4-6 1000000 1000000)" \
  "exact-id override: claude-sonnet-4-6 now 2 + 8 = 10"
assert_eq "18.000000" "$(COST cost sonnet 1000000 1000000)" \
  "exact-id override does NOT bleed into the bare family (sonnet stays 3 + 15 = 18)"
assert_contains "$(COST prices)" "overrides loaded from" \
  "prices notes when an override file is present"
rm -f "$sb/prices.tsv"

# ── prices: defaults present ──────────────────────────────────
pr="$(COST prices)"
assert_contains "$pr" "opus"   "prices lists opus"
assert_contains "$pr" "sonnet" "prices lists sonnet"
assert_contains "$pr" "haiku"  "prices lists haiku"

# ── report: aggregate by model, total, skip non-usage, sort desc ─
report_in='{"model":"claude-opus-4-7","input_tokens":1000000,"output_tokens":1000000,"ts":"2026-05-20T00:00:00Z"}
{"model":"claude-opus-4-7","input_tokens":0,"output_tokens":0,"cache_read_tokens":1000000,"ts":"2026-05-21T00:00:00Z"}
{"model":"claude-sonnet-4-6","input_tokens":2000000,"output_tokens":500000,"ts":"2026-05-21T00:00:00Z"}
{"type":"user","content":"no usage on this line"}'
rep="$(printf '%s\n' "$report_in" | COST report)"
assert_contains "$rep" "3 call(s)" "report counts only usage records (skips the user line)"
assert_contains "$rep" "91.50" "opus subtotal = 90 + 1.50 = 91.50"
assert_contains "$rep" "13.50" "sonnet subtotal = 13.50"
assert_contains "$rep" "105.00" "grand total = 105.00"
first_model="$(printf '%s\n' "$report_in" | COST report | awk '/^[[:space:]]+claude-/{print $1; exit}')"
assert_eq "claude-opus-4-7" "$first_model" "report sorts by cost desc (opus row first)"

# ── report --since filters by timestamp ───────────────────────
since_out="$(printf '%s\n' "$report_in" | COST report --since 2026-05-21)"
assert_contains "$since_out" "2 call(s)" "since drops the 2026-05-20 record"
assert_contains "$since_out" "since 2026-05-21" "report echoes the since cutoff"

# ── report parses raw Claude Code transcript lines (best-effort) ─
raw='{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":1000000}},"timestamp":"2026-05-22T00:00:00Z"}
{"type":"user","message":{"role":"user","content":"hi"}}'
raw_out="$(printf '%s\n' "$raw" | COST report)"
assert_contains "$raw_out" "1 call(s)" "raw transcript: one assistant usage line, user line skipped"
assert_contains "$raw_out" "35.25" "raw transcript cost = 15(in) + 18.75(cache_creation) + 1.50(cache_read) = 35.25"

# ── report --json ─────────────────────────────────────────────
j="$(printf '%s\n' '{"model":"opus","input_tokens":1000000,"output_tokens":0}' | COST report --json)"
assert_contains "$j" '"total_usd":15.000000' "report --json total"
assert_contains "$j" '"model":"opus"' "report --json per-model"

# ── report --input FILE ───────────────────────────────────────
printf '%s\n' '{"model":"opus","input_tokens":1000000,"output_tokens":0}' > "$sb/usage.jsonl"
assert_contains "$(COST report --input "$sb/usage.jsonl")" "15.00" "report reads --input file"

# ── savings projection ────────────────────────────────────────
sav_in='{"model":"claude-opus-4-7","input_tokens":1000000,"output_tokens":1000000}'
sav="$(printf '%s\n' "$sav_in" | COST savings --from opus --to sonnet)"
assert_contains "$sav" "72.00" "savings opus→sonnet on 1M/1M = 90 - 18 = 72"
assert_contains "$sav" "80.0%" "savings percentage = 80%"
assert_contains "$sav" "Projection only" "savings is labelled a projection, not a measured win"
savj="$(printf '%s\n' "$sav_in" | COST savings --from opus --to sonnet --json)"
assert_contains "$savj" '"savings_usd":72.000000' "savings --json amount"
assert_contains "$savj" '"savings_pct":80.00' "savings --json percent"

# ── savings: no matching 'from' usage → graceful ──────────────
nomatch="$(printf '%s\n' '{"model":"sonnet","input_tokens":1000,"output_tokens":1000}' | COST savings --from opus --to haiku)"
assert_contains "$nomatch" "No usage on opus" "savings with no matching from-model is graceful"

# ── savings: unknown from/to → exit 2 ─────────────────────────
printf '%s\n' "$sav_in" | COST savings --from opus --to gpt-4o >/dev/null 2>&1; rc=$?
assert_exit 2 "$rc" "savings with an unknown --to model → exit 2"

# ── bad / missing subcommand → exit 1 ─────────────────────────
COST bogus >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "unknown subcommand → exit 1"
COST >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "no subcommand → exit 1"

t_done
