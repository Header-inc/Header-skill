#!/usr/bin/env bash
# test/ledger.test.sh — bin/header-ledger. Uses --repo to stay independent of
# the actual git repo, and a sandboxed HEADER_HOME.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

LG="$SKILL_DIR/bin/header-ledger"
sb="$(make_sandbox)"
HH="$sb/.header"

# ── record + status ───────────────────────────────────────────
HEADER_HOME="$HH" "$LG" record applied mcp-streaming --repo r1 --title "MCP streaming"
assert_eq "applied" "$(HEADER_HOME="$HH" "$LG" status mcp-streaming --repo r1)" \
  "record applied → status applied"

# ── latest action wins ────────────────────────────────────────
HEADER_HOME="$HH" "$LG" record dismissed mcp-streaming --repo r1
assert_eq "dismissed" "$(HEADER_HOME="$HH" "$LG" status mcp-streaming --repo r1)" \
  "latest action wins → dismissed"

# ── unknown key → none ────────────────────────────────────────
assert_eq "none" "$(HEADER_HOME="$HH" "$LG" status nope --repo r1)" \
  "unknown key → none"

# ── repo scoping ──────────────────────────────────────────────
HEADER_HOME="$HH" "$LG" record applied shared --repo r1
assert_eq "none" "$(HEADER_HOME="$HH" "$LG" status shared --repo r2)" \
  "events are scoped to their repo"

# ── list is latest-disposition (dismissed excluded from applied) ─
HEADER_HOME="$HH" "$LG" record applied tool-x --repo r1 --title "Tool X"
applied_list="$(HEADER_HOME="$HH" "$LG" list --action applied --repo r1)"
assert_contains "$applied_list" "tool-x" "list --action applied includes a still-applied key"
assert_not_contains "$applied_list" "mcp-streaming" \
  "list --action applied excludes a key whose latest action is dismissed"

# ── wanted action (experiment demand) records + lists ─────────
HEADER_HOME="$HH" "$LG" record wanted exp-model-upgrade --repo r1 --title "Test opus upgrade"
assert_eq "wanted" "$(HEADER_HOME="$HH" "$LG" status exp-model-upgrade --repo r1)" \
  "record wanted → status wanted (captures experiment demand)"
assert_contains "$(HEADER_HOME="$HH" "$LG" list --action wanted --repo r1)" "exp-model-upgrade" \
  "list --action wanted surfaces demanded experiments"

# ── invalid action → exit 1 ───────────────────────────────────
HEADER_HOME="$HH" "$LG" record bogus k --repo r1 >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "invalid action → exit 1"
HEADER_HOME="$HH" "$LG" record applied "" --repo r1 >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "missing key → exit 1"

# ── --since-days filters old events ───────────────────────────
mkdir -p "$HH"
old_epoch=$(( $(date +%s) - 40 * 86400 ))
printf '{"ts":"old","epoch":%s,"repo":"r3","action":"applied","key":"ancient","title":"Old"}\n' \
  "$old_epoch" >> "$HH/ledger.jsonl"
HEADER_HOME="$HH" "$LG" record applied fresh --repo r3 --title "Fresh"
recent="$(HEADER_HOME="$HH" "$LG" list --action applied --since-days 30 --repo r3)"
assert_contains "$recent" "fresh" "since-days includes a recent applied key"
assert_not_contains "$recent" "ancient" "since-days excludes an old applied key"

# ── sed-metachar / spaces in title round-trip safely ──────────
HEADER_HOME="$HH" "$LG" record applied weird-key --repo r4 --title 'A & B / C "quoted"'
st="$(HEADER_HOME="$HH" "$LG" status weird-key --repo r4)"
assert_eq "applied" "$st" "title with metacharacters does not corrupt the record"

# ── get returns the full JSON record (provenance recovery) ─────
HEADER_HOME="$HH" "$LG" record surfaced prov-key --repo r6 \
  --title "Has provenance" --briefing b-99 --topic t-99 --source "https://ex.com/a"
rec="$(HEADER_HOME="$HH" "$LG" get prov-key --repo r6)"
assert_contains "$rec" '"key":"prov-key"'            "get returns the matching record"
assert_contains "$rec" '"briefing_id":"b-99"'        "get carries briefing_id"
assert_contains "$rec" '"topic_id":"t-99"'           "get carries topic_id"
assert_contains "$rec" '"source_url":"https://ex.com/a"' "get carries source_url"
# latest wins, and a no-match query is success (empty, exit 0)
HEADER_HOME="$HH" "$LG" record wanted prov-key --repo r6 --title "Now wanted"
assert_contains "$(HEADER_HOME="$HH" "$LG" get prov-key --repo r6)" '"action":"wanted"' \
  "get returns the latest record for a key"
rc=0; empty="$(HEADER_HOME="$HH" "$LG" get no-such-key --repo r6)" || rc=$?
assert_exit 0 "$rc" "get with no match → exit 0"
assert_eq "" "$empty" "get with no match → empty output"

# ── ledger:false disables recording ───────────────────────────
sb2="$(make_sandbox)"
HEADER_HOME="$sb2/.header" "$SKILL_DIR/bin/header-config" set ledger false
HEADER_HOME="$sb2/.header" "$LG" record applied off-key --repo r5
assert_eq "none" "$(HEADER_HOME="$sb2/.header" "$LG" status off-key --repo r5)" \
  "ledger:false → record is a no-op"

t_done
