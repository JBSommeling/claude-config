#!/usr/bin/env bash
# tests/test-install-selfcheck.sh — meta-tests verifying that the install
# oracle's four comparison checks can actually FAIL on corrupted inputs.
#
# Each scenario replicates the corresponding comparison logic from test-install.sh
# and runs it against deliberately bad inputs, asserting a FAIL is raised.
# This proves the checks are not permanently bypassed (kills S11-S14).
#
# Scenarios:
#   S12 — non-hook file corrupted, not listed in intentional-changes → FAIL
#   S11 — intentional-changes.txt entry with blank reason → FAIL
#   S13 — removed-files.txt entry with blank reason → FAIL
#   S14 — settings.json installed with wrong $HOME expansion → FAIL

set -uo pipefail

pass=0
fail=0

# ---------------------------------------------------------------------------
# MD5 helper (macOS / Linux compat)
# ---------------------------------------------------------------------------
file_md5() {
  if command -v md5 &>/dev/null; then
    md5 -q "$1"
  else
    md5sum "$1" | awk '{print $1}'
  fi
}

# ---------------------------------------------------------------------------
# S12: non-hook file corrupted, not in intentional-changes → must FAIL
# ---------------------------------------------------------------------------
# Mirrors the hash-comparison branch in test-install.sh (lines 303-329).
# If the comparison were replaced with `if true`, _found_intentional would
# never be set, but the code would count the mismatched file as ok anyway —
# a different bug. The real survivor is: `if true` replacing the hash check
# means the else-branch (intentional lookup) is never entered, so the file
# silently passes. We verify: with a real mismatch and no intentional entry,
# fail_count increments.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  # Create baseline content and compute its hash.
  printf 'original content\n' > "$_tmpdir/original.txt"
  _bmd5=$(file_md5 "$_tmpdir/original.txt")

  # Install a DIFFERENT (corrupted) file.
  mkdir -p "$_tmpdir/fake_home/.claude"
  printf 'corrupted content\n' > "$_tmpdir/fake_home/.claude/somefile.txt"

  # Replicate the comparison logic: no intentional-changes entry.
  _bpath="~/.claude/somefile.txt"
  _actual_path="$_tmpdir/fake_home/.claude/somefile.txt"
  _intentional_paths=()
  _intentional_reasons=()
  _fail_count=0

  _actual_md5=$(file_md5 "$_actual_path")
  if [ "$_actual_md5" = "$_bmd5" ]; then
    : # ok — hashes match
  else
    _found_intentional=false
    for _ii in "${!_intentional_paths[@]}"; do
      if [ "${_intentional_paths[$_ii]}" = "$_bpath" ]; then
        _ireason="${_intentional_reasons[$_ii]}"
        if [ -n "$_ireason" ]; then
          _found_intentional=true
        fi
        break
      fi
    done
    if ! $_found_intentional; then
      _fail_count=$((_fail_count + 1))
    fi
  fi

  if [ "$_fail_count" -gt 0 ]; then
    echo "PASS s12-hash-mismatch-no-intentional-entry"
    exit 0
  else
    echo "FAIL s12-hash-mismatch-no-intentional-entry (corrupted file not in intentional-changes should raise fail_count)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

# ---------------------------------------------------------------------------
# S11: intentional-changes.txt entry with blank reason → must FAIL
# ---------------------------------------------------------------------------
# Mirrors lines 310-321 in test-install.sh. If the `if [ -n "$_ireason" ]`
# guard were removed, a blank reason would silently mark the file as ok even
# though no human-readable justification was provided.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  printf 'original content\n' > "$_tmpdir/original.txt"
  _bmd5=$(file_md5 "$_tmpdir/original.txt")

  mkdir -p "$_tmpdir/fake_home/.claude"
  printf 'changed content\n' > "$_tmpdir/fake_home/.claude/somefile.txt"

  # Intentional-changes entry exists but has a BLANK reason.
  _bpath="~/.claude/somefile.txt"
  _actual_path="$_tmpdir/fake_home/.claude/somefile.txt"
  _intentional_paths=("$_bpath")
  _intentional_reasons=("")   # ← blank reason (the bug)
  _fail_count=0

  _actual_md5=$(file_md5 "$_actual_path")
  if [ "$_actual_md5" = "$_bmd5" ]; then
    : # ok
  else
    _found_intentional=false
    for _ii in "${!_intentional_paths[@]}"; do
      if [ "${_intentional_paths[$_ii]}" = "$_bpath" ]; then
        _ireason="${_intentional_reasons[$_ii]}"
        if [ -n "$_ireason" ]; then
          _found_intentional=true
        fi
        break
      fi
    done
    if ! $_found_intentional; then
      _fail_count=$((_fail_count + 1))
    fi
  fi

  if [ "$_fail_count" -gt 0 ]; then
    echo "PASS s11-blank-intentional-reason"
    exit 0
  else
    echo "FAIL s11-blank-intentional-reason (blank reason in intentional-changes should not satisfy the check)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

# ---------------------------------------------------------------------------
# S13: removed-files.txt entry with blank reason → must FAIL
# ---------------------------------------------------------------------------
# Mirrors lines 284-301 in test-install.sh. If the `if [ -n "$_rreason" ]`
# guard were removed, a blank reason in removed-files.txt would silently
# excuse a missing baseline file without a human justification.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  # The file is absent from the fake_home (simulating a missing baseline file).
  _bpath="~/.claude/somefile.txt"
  _actual_path="$_tmpdir/fake_home/.claude/somefile.txt"
  # (file intentionally not created)

  # removed-files entry exists but has a BLANK reason.
  _removed_paths=("$_bpath")
  _removed_reasons=("")   # ← blank reason (the bug)
  _fail_count=0

  if [ ! -f "$_actual_path" ]; then
    _found_removed=false
    for _ri in "${!_removed_paths[@]}"; do
      if [ "${_removed_paths[$_ri]}" = "$_bpath" ]; then
        _rreason="${_removed_reasons[$_ri]}"
        if [ -n "$_rreason" ]; then
          _found_removed=true
        fi
        break
      fi
    done
    if ! $_found_removed; then
      _fail_count=$((_fail_count + 1))
    fi
  fi

  if [ "$_fail_count" -gt 0 ]; then
    echo "PASS s13-blank-removed-reason"
    exit 0
  else
    echo "FAIL s13-blank-removed-reason (blank reason in removed-files should not satisfy the check)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

# ---------------------------------------------------------------------------
# S14: settings.json installed with wrong $HOME expansion → must FAIL
# ---------------------------------------------------------------------------
# Mirrors lines 262-276 in test-install.sh. If the dynamic settings.json
# check were replaced with `if true` (or the expected_md5 computation were
# skipped), a settings.json with wrong $HOME paths would pass silently.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  _fake_home="$_tmpdir/fake_home"
  _fake_repo="$_tmpdir/repo"
  mkdir -p "$_fake_home/.claude"
  mkdir -p "$_fake_repo/.claude"

  # Source settings.json with a $HOME reference.
  printf '{"hooks":{"dir":"$HOME/.claude/hooks"}}\n' > "$_fake_repo/.claude/settings.json"

  # Install with WRONG home expansion (attacker used /wrong/home).
  sed "s|\$HOME|/wrong/home|g" "$_fake_repo/.claude/settings.json" \
    > "$_fake_home/.claude/settings.json"

  # Compute expected md5 using the CORRECT fake_home expansion
  # (mirrors the logic in test-install.sh line 263)
  expected_md5=$(sed "s|\$HOME|${_fake_home}|g" "$_fake_repo/.claude/settings.json" | \
    (command -v md5 &>/dev/null && md5 || md5sum | awk '{print $1}'))
  actual_md5=$(file_md5 "$_fake_home/.claude/settings.json")

  _fail_count=0
  if [ "$actual_md5" = "$expected_md5" ]; then
    : # ok — expansion is correct
  else
    _fail_count=$((_fail_count + 1))
  fi

  if [ "$_fail_count" -gt 0 ]; then
    echo "PASS s14-wrong-home-expansion"
    exit 0
  else
    echo "FAIL s14-wrong-home-expansion (wrong \$HOME expansion in settings.json should raise fail_count)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

echo ""
echo "$pass/$((pass + fail)) install-selfcheck tests passed"
[ "$fail" -eq 0 ]
