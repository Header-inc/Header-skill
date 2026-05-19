#!/usr/bin/env sh
# install.sh — install the Header briefing skill.
#
#   curl -fsSL https://raw.githubusercontent.com/Header-inc/Header-skill/main/install.sh | sh
#   ./install.sh                 # from a clone of this repo
#
# Installs the header-briefing/ skill folder into your agent's skills directory
# (Claude Code, plus Codex if `codex` is on PATH). Idempotent — re-run to update.
#
# POSIX sh — no bashisms (it is commonly run piped to `sh`).
set -eu

REPO_URL="https://github.com/Header-inc/Header-skill.git"
TARBALL_URL="https://github.com/Header-inc/Header-skill/archive/refs/heads/main.tar.gz"
SKILL_NAME="header-briefing"

log() { printf '  %s\n' "$1"; }

# ── Locate the skill source ───────────────────────────────────
# Prefer a local copy (running from a clone); otherwise fetch the repo.
SRC=""
_sd="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"
if [ -n "$_sd" ] && [ -f "$_sd/$SKILL_NAME/SKILL.md" ]; then
  SRC="$_sd/$SKILL_NAME"
elif [ -f "./$SKILL_NAME/SKILL.md" ]; then
  SRC="$(pwd)/$SKILL_NAME"
fi

CLEANUP=""
if [ -z "$SRC" ]; then
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/header-install.XXXXXX")"
  CLEANUP="$TMP"
  log "Fetching Header-skill..."
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO_URL" "$TMP/repo" >/dev/null 2>&1
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMP"
    mv "$TMP"/Header-skill-* "$TMP/repo"
  else
    echo "install.sh: need git or curl to fetch the skill." >&2
    exit 1
  fi
  SRC="$TMP/repo/$SKILL_NAME"
fi

if [ ! -f "$SRC/SKILL.md" ]; then
  echo "install.sh: could not locate the $SKILL_NAME skill folder." >&2
  [ -n "$CLEANUP" ] && rm -rf "$CLEANUP"
  exit 1
fi

# ── Determine install targets ─────────────────────────────────
TARGETS="$HOME/.claude/skills"
if command -v codex >/dev/null 2>&1; then
  TARGETS="$TARGETS $HOME/.codex/skills"
fi

# ── Install ───────────────────────────────────────────────────
for base in $TARGETS; do
  dest="$base/$SKILL_NAME"
  verb="Installed"
  [ -d "$dest" ] && verb="Updated"
  mkdir -p "$base"
  rm -rf "$dest"
  cp -R "$SRC" "$dest"
  rm -rf "$dest/.git"
  chmod +x "$dest/bin/"* 2>/dev/null || true
  [ -f "$dest/test/run.sh" ] && chmod +x "$dest/test/run.sh" 2>/dev/null || true
  log "$verb -> $dest"
done

[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"

log ""
log "Done. Start a new agent session, then run: /header-briefing"
