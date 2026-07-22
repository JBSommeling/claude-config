#!/usr/bin/env bash
# tests/test-install.sh — FR2 regression test for install.sh --claude
#
# Verifies that the Claude install produces the same content as the baseline
# manifest captured at bb5a313.
#
# Rules:
#   Non-hook, non-settings files  — MUST exist and md5 MUST match baseline
#   settings.json                 — MUST exist; md5 verified dynamically
#                                   (baseline used real $HOME; we expand with FAKE_HOME)
#   Hook files (~/.claude/hooks/) — expected to have changed (T3b/T3c refactor);
#                                   reported as "changed (expected)", never fail
#   New files not in baseline     — reported as "new files", never fail
#
# Usage: bash tests/test-install.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$REPO_ROOT/tests/baseline-manifest.txt"
INSTALL="$REPO_ROOT/install.sh"

# --------------------------------------------------------------------------
# MD5 helper — works on macOS (md5 -q) and Linux (md5sum)
# --------------------------------------------------------------------------
file_md5() {
  if command -v md5 &>/dev/null; then
    md5 -q "$1"
  else
    md5sum "$1" | awk '{print $1}'
  fi
}

# --------------------------------------------------------------------------
# Setup — temporary fake HOME
# --------------------------------------------------------------------------
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT

echo "Temporary HOME: $FAKE_HOME"
echo "Running: install.sh --claude"
echo ""

# Run the Claude install with the fake HOME; Claude writes by default (no --apply needed)
HOME="$FAKE_HOME" bash "$INSTALL" --claude > /dev/null 2>&1

# --------------------------------------------------------------------------
# Parse baseline manifest
# Build associative arrays: path → expected_md5
# --------------------------------------------------------------------------

# We use regular arrays and parallel lookup for bash 3 compat (macOS ships bash 3)
baseline_paths=()
baseline_md5s=()

while IFS= read -r line; do
  # Skip comments and blank lines
  [[ "$line" =~ ^#  ]] && continue
  [[ -z "$line"     ]] && continue

  # Format: <path>  <md5>
  bpath="${line%%  *}"
  bmd5="${line##*  }"
  baseline_paths+=("$bpath")
  baseline_md5s+=("$bmd5")
done < "$BASELINE"

# --------------------------------------------------------------------------
# Enumerate every installed file under the fake HOME
# --------------------------------------------------------------------------
installed_files=()
while IFS= read -r f; do
  installed_files+=("$f")
done < <(find "$FAKE_HOME" -type f | sort)

# --------------------------------------------------------------------------
# Compare installed files against baseline
# --------------------------------------------------------------------------
pass_count=0
fail_count=0
fail_messages=()

hook_reports=()         # "changed (expected)" or "missing (expected)"
new_files=()            # installed but not in baseline

settings_target="${FAKE_HOME}/.claude/settings.json"

echo "--- Non-hook files vs baseline ---"

for i in "${!baseline_paths[@]}"; do
  bpath="${baseline_paths[$i]}"
  bmd5="${baseline_md5s[$i]}"

  # Expand ~ to FAKE_HOME for the actual path
  actual_path="${bpath/#\~/$FAKE_HOME}"

  # Classify: hooks vs settings vs everything else
  # Note: keep the literal ~ here; bpath values come from the manifest as-is
  if [[ "$bpath" == "~/.claude/hooks/"* ]]; then
    # Hook file — expected-difference, never fail
    if [ -f "$actual_path" ]; then
      installed_md5=$(file_md5 "$actual_path")
      if [ "$installed_md5" = "$bmd5" ]; then
        hook_reports+=("  matched (unexpected — was expected to change): $bpath")
      else
        hook_reports+=("  changed (expected): $bpath")
      fi
    else
      hook_reports+=("  missing (expected — file renamed or removed): $bpath")
    fi
    continue
  fi

  if [[ "$bpath" == "~/.claude/settings.json" ]]; then
    # settings.json — verify dynamically (baseline md5 used real $HOME)
    if [ ! -f "$actual_path" ]; then
      echo "  FAIL: $bpath (missing)"
      fail_count=$((fail_count + 1))
      fail_messages+=("MISSING: $bpath")
    else
      # Compute expected md5 using the fake HOME expansion
      expected_md5=$(sed "s|\$HOME|${FAKE_HOME}|g" "${REPO_ROOT}/.claude/settings.json" | \
        (command -v md5 &>/dev/null && md5 || md5sum | awk '{print $1}'))
      actual_md5=$(file_md5 "$actual_path")
      if [ "$actual_md5" = "$expected_md5" ]; then
        echo "  ok (dynamic): $bpath (settings.json \$HOME expansion correct)"
        pass_count=$((pass_count + 1))
      else
        echo "  FAIL: $bpath (settings.json md5 mismatch)"
        echo "        expected (dynamic): $expected_md5"
        echo "        actual:             $actual_md5"
        fail_count=$((fail_count + 1))
        fail_messages+=("MD5 MISMATCH (settings.json): $bpath")
      fi
    fi
    continue
  fi

  # Regular file — must exist and md5 must match baseline exactly
  if [ ! -f "$actual_path" ]; then
    echo "  FAIL: $bpath (missing)"
    fail_count=$((fail_count + 1))
    fail_messages+=("MISSING: $bpath")
  else
    actual_md5=$(file_md5 "$actual_path")
    if [ "$actual_md5" = "$bmd5" ]; then
      echo "  ok: $bpath"
      pass_count=$((pass_count + 1))
    else
      echo "  FAIL: $bpath (md5 mismatch)"
      echo "        baseline: $bmd5"
      echo "        actual:   $actual_md5"
      fail_count=$((fail_count + 1))
      fail_messages+=("MD5 MISMATCH: $bpath")
    fi
  fi
done

# --------------------------------------------------------------------------
# Report hook files (expected-changed — not counted toward pass/fail)
# --------------------------------------------------------------------------
echo ""
echo "--- Hook files (expected-changed, not counted) ---"
if [ "${#hook_reports[@]}" -gt 0 ]; then
  # bash 3 compat: guard non-empty expansion before iterating
  for msg in "${hook_reports[@]+"${hook_reports[@]}"}"; do
    echo "$msg"
  done
else
  echo "  (none in baseline)"
fi

# --------------------------------------------------------------------------
# Detect new files installed but not in baseline
# --------------------------------------------------------------------------
echo ""
echo "--- New files (not in baseline) ---"

for installed in "${installed_files[@]}"; do
  # Convert installed path back to ~ form for lookup
  # Note: ~ in parameter substitution replacement is NOT shell-expanded, so
  # this produces a literal "~" prefix, matching the baseline manifest format.
  tilde_path="~${installed#"$FAKE_HOME"}"

  found=false
  for bp in "${baseline_paths[@]}"; do
    if [ "$bp" = "$tilde_path" ]; then
      found=true
      break
    fi
  done

  if ! $found; then
    new_files+=("  new: $tilde_path")
  fi
done

if [ "${#new_files[@]}" -gt 0 ]; then
  # bash 3 compat: guard non-empty expansion before iterating
  for nf in "${new_files[@]+"${new_files[@]}"}"; do
    echo "$nf"
  done
else
  echo "  (none)"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "--- Summary ---"
echo "  ${pass_count} files matched baseline"
echo "  ${#hook_reports[@]} hook entries (expected-changed, not counted)"
echo "  ${#new_files[@]} new files (not in baseline)"

if [ "${fail_count}" -gt 0 ]; then
  echo "  ${fail_count} FAILURES:"
  for msg in "${fail_messages[@]+"${fail_messages[@]}"}"; do
    echo "    - $msg"
  done
  echo ""
  echo "FAIL install-claude"
  exit 1
else
  echo ""
  echo "PASS install-claude"
  exit 0
fi
