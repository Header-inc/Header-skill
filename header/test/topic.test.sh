#!/usr/bin/env bash
# test/topic.test.sh — bin/header-topic. Deterministic topic create + bind + the
# briefing-status primitive. Hermetic: the POST/GET are stubbed via
# HEADER_TOPIC_STUB / HEADER_TOPIC_STATUS_STUB so no network is touched.
#
# The stub deliberately mirrors the REAL create response — the topic object nests
# `latest_briefing:{"id":…}`, so a naive "the only bare \"id\" is topic.id" parse
# grabs the wrong one. The suite pins topic.id = the FIRST id (the regression that
# bit the live dogfood: TOPIC_ID came back equal to the briefing id).
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

HT="$SKILL_DIR/bin/header-topic"
RP="$SKILL_DIR/bin/header-repo"

# A create response shaped like prod: topic.id (TID-111) precedes the nested
# latest_briefing.id (BID-333), and first_briefing_id (BID-333) is a sibling.
mk_resp() {
  cat > "$1" <<'JSON'
{"topic":{"id":"TID-111-aaaa","name":"My Topic","description":"","owner_id":"acct_x","is_public":false,"created_at":"2026-07-07T00:00:00Z","updated_at":"2026-07-07T00:00:00Z","source_group_ids":["sg-1"],"default_goal_id":"GID-222-bbbb","default_goal_description":"...","keywords":[],"briefing_length":null,"source_count":1,"latest_briefing":{"id":"BID-333-cccc","status":"IN_PROGRESS","summary":""}},"first_briefing_id":"BID-333-cccc"}
JSON
}

# ── create: parses the nested ids correctly + binds topic.id ──
sb="$(make_sandbox)"; HH="$sb/.header"; mk_resp "$sb/resp.json"
out="$(env -u HEADER_API_KEY HEADER_HOME="$HH" HEADER_API_KEY=hdr_sk_x HEADER_REPO_KEY=r1 \
  HEADER_TOPIC_STUB="$sb/resp.json" "$HT" create --name "My Topic" --goal "some stack")"
assert_contains "$out" "TOPIC_ID TID-111-aaaa"   "topic.id is the FIRST id (not the nested briefing id)"
assert_not_contains "$out" "TOPIC_ID BID-333"    "topic.id must not be the briefing id (the live-dogfood bug)"
assert_contains "$out" "GOAL_ID GID-222-bbbb"    "default_goal_id parsed"
assert_contains "$out" "BRIEFING_ID BID-333-cccc" "first_briefing_id parsed (the poll target)"
assert_eq "TID-111-aaaa" "$(HEADER_HOME="$HH" HEADER_REPO_KEY=r1 "$RP" get)" \
  "create binds the TOPIC id to this repo (not the briefing id)"

# ── --no-bind: creates but leaves the binding untouched ──
sb="$(make_sandbox)"; HH="$sb/.header"; mk_resp "$sb/resp.json"
env -u HEADER_API_KEY HEADER_HOME="$HH" HEADER_API_KEY=hdr_sk_x HEADER_REPO_KEY=r2 \
  HEADER_TOPIC_STUB="$sb/resp.json" "$HT" create --no-bind --name N --goal G >/dev/null
assert_eq "" "$(HEADER_HOME="$HH" HEADER_REPO_KEY=r2 "$RP" get)" \
  "--no-bind creates without binding"

# ── no key → exit 2 ──
rc=0; env -u HEADER_API_KEY HEADER_HOME="$sb/empty" "$HT" create --name N --goal G >/dev/null 2>&1 || rc=$?
assert_exit 2 "$rc" "no API key → exit 2"

# ── tier gate (403 + flat error_code) → exit 3 + ERROR_CODE line ──
sb="$(make_sandbox)"; printf '{"error_code":"TOPIC_LIMIT_FREE","message":"Pro only"}' > "$sb/err.json"
rc=0; out="$(env -u HEADER_API_KEY HEADER_HOME="$sb/.header" HEADER_API_KEY=hdr_sk_x \
  HEADER_TOPIC_STUB="$sb/err.json" HEADER_TOPIC_STUB_CODE=403 "$HT" create --name N --goal G 2>/dev/null)" || rc=$?
assert_exit 3 "$rc" "tier-gate (403) → exit 3"
assert_contains "$out" "ERROR_CODE TOPIC_LIMIT_FREE" "surfaces the flat error_code for the trial/upgrade flow"

# ── missing required flags → exit 1 ──
rc=0; HEADER_HOME="$sb/.header" HEADER_API_KEY=hdr_sk_x "$HT" create --goal G >/dev/null 2>&1 || rc=$?
assert_exit 1 "$rc" "create without --name → exit 1"

# ── status: parses the briefing status word ──
sb="$(make_sandbox)"; printf '{"id":"b","status":"COMPLETED","summary":"x"}' > "$sb/st.json"
assert_eq "COMPLETED" \
  "$(HEADER_HOME="$sb/.header" HEADER_TOPIC_STATUS_STUB="$sb/st.json" "$HT" status b)" \
  "status parses COMPLETED"
printf '{"id":"b","status":"IN_PROGRESS"}' > "$sb/st.json"
assert_eq "IN_PROGRESS" \
  "$(HEADER_HOME="$sb/.header" HEADER_TOPIC_STATUS_STUB="$sb/st.json" "$HT" status b)" \
  "status parses IN_PROGRESS"
rc=0; HEADER_HOME="$sb/.header" HEADER_TOPIC_STATUS_STUB="$sb/st.json" "$HT" status >/dev/null 2>&1 || rc=$?
assert_exit 1 "$rc" "status without a briefing id → exit 1"

# ── dispatch ──
HEADER_HOME="$HH" "$HT" --help >/dev/null 2>&1; assert_exit 0 "$?" "--help exits 0"
HEADER_HOME="$HH" "$HT" zzz >/dev/null 2>&1; assert_exit 1 "$?" "unknown subcommand exits 1"

t_done
