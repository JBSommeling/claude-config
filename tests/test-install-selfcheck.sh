#!/usr/bin/env bash
# tests/test-install-selfcheck.sh — "oracle of the oracle"
#
# Proves that tests/test-install.sh (the real install oracle) actually FAILS
# when the installed tree does not match the expected baseline. Runs the REAL
# oracle against a deliberately-corrupted baseline in a throwaway copy of the
# repo, then asserts a non-zero exit.
#
# This replaces the former mirror-based self-check, which tested a private
# copy of the comparison logic rather than the real script.

set -uo pipefail

pass=0
fail=0

_selfdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo="$(cd "$_selfdir/.." && pwd)"

# ---------------------------------------------------------------------------
# Create a throwaway copy of the repo
# ---------------------------------------------------------------------------
_copy=$(mktemp -d)
trap 'rm -rf "$_copy"' EXIT

if command -v rsync &>/dev/null; then
  rsync -a --exclude=.git "$_repo/" "$_copy/"
else
  cp -R "$_repo/." "$_copy/"
fi

# ---------------------------------------------------------------------------
# Pick a target line to corrupt programmatically:
#   - path starts with ~/.claude/
#   - NOT under ~/.claude/hooks/
#   - NOT ~/.claude/settings.json
#   - NOT listed in tests/intentional-changes.txt
#   - NOT listed in tests/removed-files.txt
#
# This guarantees the corruption flows through the plain hash-comparison
# branch with no allowlist excuse.
# ---------------------------------------------------------------------------
_manifest="$_copy/tests/baseline-manifest.txt"
_ic_file="$_copy/tests/intentional-changes.txt"
_rf_file="$_copy/tests/removed-files.txt"

_target_path=""

while IFS= read -r _line; do
  [[ "$_line" =~ ^# ]] && continue
  [[ -z "$_line"     ]] && continue

  # Format: <path>  <md5>  (two-space separator)
  _bpath="${_line%%  *}"

  # Must start with ~/.claude/  (escape ~ to prevent tilde-expansion in case)
  case "$_bpath" in
    \~/.claude/*) ;;
    *) continue ;;
  esac

  # Must NOT be under ~/.claude/hooks/
  case "$_bpath" in
    \~/.claude/hooks/*) continue ;;
  esac

  # Must NOT be settings.json
  [ "$_bpath" = "~/.claude/settings.json" ] && continue

  # Must NOT appear in intentional-changes.txt (format: path | reason)
  if grep -qF "$_bpath |" "$_ic_file" 2>/dev/null; then
    continue
  fi

  # Must NOT appear in removed-files.txt (format: path | reason)
  if grep -qF "$_bpath |" "$_rf_file" 2>/dev/null; then
    continue
  fi

  _target_path="$_bpath"
  break
done < "$_manifest"

if [ -z "$_target_path" ]; then
  echo "FAIL oracle-detects-baseline-mismatch: could not find a suitable baseline line to corrupt"
  fail=$((fail + 1))
  echo "$pass/$((pass+fail)) install-selfcheck tests passed"
  [ "$fail" -eq 0 ]
  exit $?
fi

# ---------------------------------------------------------------------------
# Corrupt only that line's md5 to a wrong-but-valid 32-char hex value.
# Write to a temp file first, then cp over (avoids in-place editors).
# ---------------------------------------------------------------------------
_bad_md5="00000000000000000000000000000000"
_tmp_manifest="$_copy/.manifest.tmp"

while IFS= read -r _line; do
  _bpath="${_line%%  *}"
  if [ "$_bpath" = "$_target_path" ]; then
    printf '%s  %s\n' "$_target_path" "$_bad_md5"
  else
    printf '%s\n' "$_line"
  fi
done < "$_manifest" > "$_tmp_manifest"

cp "$_tmp_manifest" "$_manifest"

# ---------------------------------------------------------------------------
# Run the REAL oracle in the copy
# ---------------------------------------------------------------------------
bash "$_copy/tests/test-install.sh" >/dev/null 2>&1
_rc=$?

# ---------------------------------------------------------------------------
# Assert non-zero exit
# ---------------------------------------------------------------------------
if [ "$_rc" -ne 0 ]; then
  echo "PASS oracle-detects-baseline-mismatch ($_target_path)"
  pass=$((pass + 1))
else
  echo "FAIL oracle-detects-baseline-mismatch ($_target_path): real test-install.sh passed despite a corrupted expected baseline — the actual-vs-expected comparison is not firing"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Scenario 2: codex-oracle-detects-broken-command
#
# Proves the Codex config.toml command-path check in test-install.sh actually
# fires — the oracle must fail when a command path referenced by config.toml
# does not exist after `--codex --apply`. Surgically trips only that check.
# ---------------------------------------------------------------------------
_copy2=$(mktemp -d)
trap 'rm -rf "$_copy" "$_copy2"' EXIT

if command -v rsync &>/dev/null; then
  rsync -a --exclude=.git "$_repo/" "$_copy2/"
else
  cp -R "$_repo/." "$_copy2/"
fi

_codex_toml="$_copy2/.codex/config.toml"
_bogus_path='$HOME/.codex/hooks/__selfcheck_absent_sentinel__.sh'
_tmp_toml="${_codex_toml}.tmp"

# Rewrite the FIRST matching command line to point at the bogus sentinel.
# Write to a temp file then cp — no in-place editors.
_s2_matched=0
_s2_cmd_display=""
while IFS= read -r _line; do
  if [ "$_s2_matched" -eq 0 ] && printf '%s\n' "$_line" | grep -qE '^[[:space:]]*command[[:space:]]*=[[:space:]]*"'; then
    _s2_matched=1
    _mutated=$(printf '%s\n' "$_line" | sed "s|\"[^\"]*\"|\"${_bogus_path}\"|")
    _s2_cmd_display=$(printf '%s\n' "$_mutated" | sed -E 's/^[[:space:]]*command[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    printf '%s\n' "$_mutated"
  else
    printf '%s\n' "$_line"
  fi
done < "$_codex_toml" > "$_tmp_toml"
cp "$_tmp_toml" "$_codex_toml"

if [ "$_s2_matched" -eq 0 ]; then
  echo "FAIL codex-oracle-detects-broken-command: no 'command = \"...\"' line found in .codex/config.toml — cannot perform mutation"
  fail=$((fail + 1))
else
  bash "$_copy2/tests/test-install.sh" >/dev/null 2>&1
  _rc2=$?
  if [ "$_rc2" -ne 0 ]; then
    echo "PASS codex-oracle-detects-broken-command ($_s2_cmd_display)"
    pass=$((pass + 1))
  else
    echo "FAIL codex-oracle-detects-broken-command: real test-install.sh passed despite a broken Codex config.toml command path — the Codex command-path check is not firing"
    fail=$((fail + 1))
  fi
fi

echo "$pass/$((pass+fail)) install-selfcheck tests passed"
[ "$fail" -eq 0 ]
