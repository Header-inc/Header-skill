#!/usr/bin/env bash
# test/preamble.test.sh — extracts the "## Preamble" bash block from the SHIPPED
# SKILL.md and runs it sandboxed. This verifies the extracted bash logic; that a
# harness actually executes the block is covered by the manual E2E checklist in
# the plan, not here.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

# Extract the first ```bash block under the "## Preamble" heading.
PREAMBLE="$(awk '
  /^## Preamble/                 { inpre = 1 }
  inpre && /^```bash/            { incode = 1; next }
  inpre && incode && /^```/      { exit }
  inpre && incode               { print }
' "$SKILL_DIR/SKILL.md")"

assert_contains "$PREAMBLE" "HEADER_MODE:" "preamble bash block extracted from SKILL.md"

# run_preamble <skill_dir_token> <home> [EXTRA_ENV=val ...]
# Substitutes {SKILL_DIR}, runs the block in a clean env, returns stdout+stderr.
run_preamble() {
  local sdir="$1" home="$2"; shift 2
  local block
  block="$(printf '%s' "$PREAMBLE" | sed "s|{SKILL_DIR}|$sdir|g")"
  env -i PATH="$PATH" HOME="$home" HEADER_HOME="$home/.header" "$@" bash -c "$block" 2>&1
}

# ── classic mode: nothing resolves ────────────────────────────
sb="$(make_sandbox)"
out="$(run_preamble "$sb/nope" "$sb")"
assert_contains "$out" "HEADER_MODE: classic" "no bin/ anywhere → classic mode"
assert_contains "$out" "HEADER_NOTICE:" "classic mode prints the reinstall notice"

# ── enterprise via {SKILL_DIR} ────────────────────────────────
sb="$(make_sandbox)"
out="$(run_preamble "$SKILL_DIR" "$sb")"
assert_contains "$out" "HEADER_MODE: enterprise" "{SKILL_DIR} with bin/ → enterprise mode"
assert_contains "$out" "HEADER_BIN: $SKILL_DIR/bin/header-config" "HEADER_BIN echoes the resolved header-config path"
assert_eq "yes" "$([ -d "$sb/.header" ] && echo yes || echo no)" "enterprise mode creates ~/.header"

# ── enterprise via a hardcoded fallback path ──────────────────
sb="$(make_sandbox)"
mkdir -p "$sb/.claude/skills/header-briefing/bin"
cp "$SKILL_DIR/bin/header-config" "$sb/.claude/skills/header-briefing/bin/header-config"
chmod +x "$sb/.claude/skills/header-briefing/bin/header-config"
out="$(run_preamble "$sb/bogus-not-real" "$sb")"
assert_contains "$out" "HEADER_MODE: enterprise" "fallback path ~/.claude/skills/... resolves → enterprise"

# ── interactivity — ★ non-interactive regression ──────────────
sb="$(make_sandbox)"
out="$(run_preamble "$SKILL_DIR" "$sb")"
assert_contains "$out" "INTERACTIVE: yes" "no CI / HEADER_NONINTERACTIVE → interactive"
out="$(run_preamble "$SKILL_DIR" "$sb" CI=1)"
assert_contains "$out" "INTERACTIVE: no" "★ CI=1 → non-interactive (scheduled-run guard holds)"
out="$(run_preamble "$SKILL_DIR" "$sb" HEADER_NONINTERACTIVE=1)"
assert_contains "$out" "INTERACTIVE: no" "★ HEADER_NONINTERACTIVE=1 → non-interactive"

# ── config values echoed (env > config > default) ─────────────
sb="$(make_sandbox)"
out="$(run_preamble "$SKILL_DIR" "$sb")"
assert_contains "$out" "LANGUAGE: English" "LANGUAGE echoed — default English"
assert_contains "$out" "STALENESS_DAYS: 7" "STALENESS_DAYS echoed — default 7"
out="$(run_preamble "$SKILL_DIR" "$sb" HEADER_LANGUAGE=Klingon)"
assert_contains "$out" "LANGUAGE: Klingon" "HEADER_LANGUAGE env overrides the default"

# ── REPO_TOPIC (per-repo binding) ─────────────────────────────
sb="$(make_sandbox)"; mkdir -p "$sb/.header"
assert_contains "$(run_preamble "$SKILL_DIR" "$sb")" "REPO_TOPIC:" \
  "REPO_TOPIC echoed (empty when this repo has no binding)"
printf '{"key":"k1","topic":"bound-xyz","name":"X"}\n' > "$sb/.header/repos.jsonl"
assert_contains "$(run_preamble "$SKILL_DIR" "$sb" HEADER_REPO_KEY=k1)" "REPO_TOPIC: bound-xyz" \
  "REPO_TOPIC echoes the topic bound to this repo"

# ── markers ───────────────────────────────────────────────────
sb="$(make_sandbox)"; mkdir -p "$sb/.header"
out="$(run_preamble "$SKILL_DIR" "$sb")"
assert_contains "$out" "WELCOME_SEEN: no" "no marker → WELCOME_SEEN: no"
assert_contains "$out" "LANGUAGE_PROMPTED: no" "no marker → LANGUAGE_PROMPTED: no"
assert_contains "$out" "SIGNUP_STATE: unset" "no .signup-state file → SIGNUP_STATE: unset"
assert_contains "$out" "TELEMETRY_PROMPTED: no" "no marker → TELEMETRY_PROMPTED: no"
touch "$sb/.header/.welcome-seen"
touch "$sb/.header/.language-prompted"
printf 'public-only\n' > "$sb/.header/.signup-state"
touch "$sb/.header/.telemetry-prompted"
out="$(run_preamble "$SKILL_DIR" "$sb")"
assert_contains "$out" "WELCOME_SEEN: yes" ".welcome-seen marker → WELCOME_SEEN: yes"
assert_contains "$out" "LANGUAGE_PROMPTED: yes" ".language-prompted marker → LANGUAGE_PROMPTED: yes"
assert_contains "$out" "SIGNUP_STATE: public-only" ".signup-state value echoed"
assert_contains "$out" "TELEMETRY_PROMPTED: yes" ".telemetry-prompted marker → TELEMETRY_PROMPTED: yes"

# ── HAS_KEY ───────────────────────────────────────────────────
sb="$(make_sandbox)"
assert_contains "$(run_preamble "$SKILL_DIR" "$sb")" "HAS_KEY: no" \
  "no key anywhere → HAS_KEY: no"
assert_contains "$(run_preamble "$SKILL_DIR" "$sb" HEADER_API_KEY=hdr_sk_x)" "HAS_KEY: yes" \
  "HEADER_API_KEY env → HAS_KEY: yes"
sb="$(make_sandbox)"; mkdir -p "$sb/.header"
printf 'HEADER_API_KEY=hdr_sk_fromfile\n' > "$sb/.header/credentials"
assert_contains "$(run_preamble "$SKILL_DIR" "$sb")" "HAS_KEY: yes" \
  "credentials file containing a key → HAS_KEY: yes"

# ── credentials file is parsed, never sourced/executed ────────
sb="$(make_sandbox)"; mkdir -p "$sb/.header"
printf 'HEADER_API_KEY=hdr_sk_x\necho PWNED_BY_SOURCE\n' > "$sb/.header/credentials"
assert_not_contains "$(run_preamble "$SKILL_DIR" "$sb")" "PWNED" \
  "credentials file is read as data — never sourced or executed"

# ── update check surfaces actionable states (injected endpoint) ─
sb="$(make_sandbox)"
assert_contains "$(run_preamble "$SKILL_DIR" "$sb" HEADER_VERSION_JSON='{"latest":"99.0.0"}')" \
  "UPDATE_CHECK: UPDATE_AVAILABLE" "preamble surfaces an available update"
sb="$(make_sandbox)"
_lv="$(tr -d '[:space:]' < "$SKILL_DIR/VERSION")"
assert_not_contains "$(run_preamble "$SKILL_DIR" "$sb" HEADER_VERSION_JSON="{\"latest\":\"$_lv\"}")" \
  "UPDATE_CHECK:" "preamble stays quiet when up to date"
sb="$(make_sandbox)"
HEADER_HOME="$sb/.header" "$SKILL_DIR/bin/header-config" set update_check false
assert_not_contains "$(run_preamble "$SKILL_DIR" "$sb" HEADER_VERSION_JSON='{"latest":"99.0.0"}')" \
  "UPDATE_CHECK:" "update_check=false → preamble surfaces nothing"

t_done
