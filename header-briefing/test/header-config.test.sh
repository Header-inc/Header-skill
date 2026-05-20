#!/usr/bin/env bash
# test/header-config.test.sh — unit tests for bin/header-config.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

HC="$SKILL_DIR/bin/header-config"

# ── get: defaults (missing file) ──────────────────────────────
sb="$(make_sandbox)"
assert_eq "English" "$(HEADER_HOME="$sb/.header" "$HC" get language)" \
  "get language on missing file → default English"
assert_eq "7" "$(HEADER_HOME="$sb/.header" "$HC" get staleness_days)" \
  "get staleness_days on missing file → default 7"
assert_eq "" "$(HEADER_HOME="$sb/.header" "$HC" get default_topic)" \
  "get default_topic on missing file → empty default"
assert_eq "true" "$(HEADER_HOME="$sb/.header" "$HC" get update_check)" \
  "get update_check on missing file → default true"
assert_eq "false" "$(HEADER_HOME="$sb/.header" "$HC" get auto_update)" \
  "get auto_update on missing file → default false"

# ── set then get; header written on first create ──────────────
HEADER_HOME="$sb/.header" "$HC" set language Turkish
assert_eq "Turkish" "$(HEADER_HOME="$sb/.header" "$HC" get language)" \
  "set then get language → Turkish"
assert_contains "$(cat "$sb/.header/config")" "Header skill config" \
  "first set writes the terse config header"

# ── overwrite an existing key (sed replace path) ──────────────
HEADER_HOME="$sb/.header" "$HC" set language Spanish
assert_eq "Spanish" "$(HEADER_HOME="$sb/.header" "$HC" get language)" \
  "overwrite language → Spanish"
assert_eq "1" "$(grep -c '^language:' "$sb/.header/config")" \
  "overwrite replaces in place — only one language line"

# ── new key appends ───────────────────────────────────────────
HEADER_HOME="$sb/.header" "$HC" set staleness_days 14
assert_eq "14" "$(HEADER_HOME="$sb/.header" "$HC" get staleness_days)" \
  "set new key staleness_days → 14"

# ── sed-metacharacter values round-trip (append + replace) ────
sb2="$(make_sandbox)"
HEADER_HOME="$sb2/.header" "$HC" set default_topic 'a/b&c\d'
assert_eq 'a/b&c\d' "$(HEADER_HOME="$sb2/.header" "$HC" get default_topic)" \
  "metachar value round-trips via the append path"
HEADER_HOME="$sb2/.header" "$HC" set default_topic 'x&y/z'
assert_eq 'x&y/z' "$(HEADER_HOME="$sb2/.header" "$HC" get default_topic)" \
  "metachar value round-trips via the sed-replace path"

# ── embedded newline → first line only ────────────────────────
HEADER_HOME="$sb2/.header" "$HC" set language "$(printf 'Line1\nLine2')"
assert_eq "Line1" "$(HEADER_HOME="$sb2/.header" "$HC" get language)" \
  "value with embedded newline → only first line stored"

# ── invalid keys → exit 1 ─────────────────────────────────────
HEADER_HOME="$sb2/.header" "$HC" get 'bad key' >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "get with invalid key → exit 1"
HEADER_HOME="$sb2/.header" "$HC" set 'bad-key' x >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "set with invalid key → exit 1"

# ── duplicate / malformed lines ───────────────────────────────
sb3="$(make_sandbox)"; mkdir -p "$sb3/.header"
printf 'language: First\nlanguage: Last\n' > "$sb3/.header/config"
assert_eq "Last" "$(HEADER_HOME="$sb3/.header" "$HC" get language)" \
  "duplicate key lines → last wins"
printf 'this is not a config line\nlanguage: Italian\n' > "$sb3/.header/config"
assert_eq "Italian" "$(HEADER_HOME="$sb3/.header" "$HC" get language)" \
  "malformed line ignored, real value still found"

# ── list / defaults ───────────────────────────────────────────
list_out="$(HEADER_HOME="$sb3/.header" "$HC" list)"
assert_contains "$list_out" "language:" "list shows the language key"
assert_contains "$list_out" "(set)"     "list marks file-set values as (set)"
def_out="$(HEADER_HOME="$sb3/.header" "$HC" defaults)"
assert_contains "$def_out" "staleness_days:" "defaults lists staleness_days"
assert_contains "$def_out" "default_topic:"  "defaults lists default_topic"
assert_contains "$def_out" "auto_update:"    "defaults lists auto_update"
assert_contains "$def_out" "update_check:"   "defaults lists update_check"

# ── unknown / missing subcommand → exit 1 ─────────────────────
"$HC" bogus >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "unknown subcommand → exit 1"
"$HC" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "no subcommand → exit 1"

t_done
