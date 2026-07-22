#!/usr/bin/env bash
# .githooks/cochange.sh — release-invariant check.
#
# `header/SKILL.md` and `header/VERSION` moved together in 15 of 20 commits;
# `CHANGELOG.md` and `header/VERSION`, in 15 of 15. The five misses are the bug:
# a behavior change that ships without a version bump is invisible to
# bin/header-update-check on every installed machine, so nobody pulls it.
#
# This fails the commit when a staged behavior change is missing its companion.
# Deliberate exception (a typo fix, a doc-only tweak): git commit --no-verify.
set -uo pipefail

_staged="$(git diff --cached --name-only --diff-filter=ACMR)"
_has() { printf '%s\n' "$_staged" | grep -qx "$1"; }

_rc=0
_fail() { printf '✗ release invariant: %s\n' "$1" >&2; _rc=1; }

if _has 'header/SKILL.md'; then
  _has 'header/VERSION'  || _fail 'header/SKILL.md is staged without header/VERSION — bump the version so installed machines see the change.'
  _has 'CHANGELOG.md'    || _fail 'header/SKILL.md is staged without CHANGELOG.md — record what changed.'
fi

if _has 'header/VERSION' && ! _has 'CHANGELOG.md'; then
  _fail 'header/VERSION is staged without CHANGELOG.md — these have moved together in every commit so far.'
fi

if [ "$_rc" -ne 0 ]; then
  printf '  Stage the companion file, or bypass deliberately with: git commit --no-verify\n' >&2
  exit 1
fi
exit 0
