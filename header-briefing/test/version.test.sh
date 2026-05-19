#!/usr/bin/env bash
# test/version.test.sh — the VERSION file and the SKILL.md frontmatter version:
# must agree. VERSION is canonical; the frontmatter mirrors it.
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

file_version="$(cat "$SKILL_DIR/VERSION" 2>/dev/null | head -1 | tr -d '[:space:]')"

# Extract version: from inside the SKILL.md frontmatter only (between the first
# two `---` lines), so a stray `version:` elsewhere can't match.
fm_version="$(awk '
  /^---$/ { n++; next }
  n == 1 && /^version:/ { sub(/^version:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }
' "$SKILL_DIR/SKILL.md")"

assert_contains "$file_version" "." "VERSION file looks like a dotted version"
assert_eq "$file_version" "$fm_version" \
  "SKILL.md frontmatter version: matches the VERSION file"

t_done
