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
#   Hook files (~/.claude/hooks/) that EXIST but differ in md5
#                                 — reported as "changed (expected)", never fail
#   Hook files that are MISSING   — FAIL unless the basename appears in
#                                   tests/renamed-hooks.txt AND the replacement
#                                   exists and is executable after install
#   New files not in baseline     — reported as "new files", never fail
#
# Additionally, every `command` path in .claude/settings.json and
# .codex/config.toml is verified to exist and be executable after install.
# This catches dead hook registrations (C1/C2 fix).
#
# Usage: bash tests/test-install.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$REPO_ROOT/tests/baseline-manifest.txt"
INTENTIONAL_CHANGES_FILE="$REPO_ROOT/tests/intentional-changes.txt"
REMOVED_FILES_FILE="$REPO_ROOT/tests/removed-files.txt"
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

hook_reports=()         # "changed (expected)" or "renamed (expected)" entries
new_files=()            # installed but not in baseline

settings_target="${FAKE_HOME}/.claude/settings.json"

# Load the renamed-hooks allowlist (basename-only lines: old -> new)
RENAMED_HOOKS_FILE="$REPO_ROOT/tests/renamed-hooks.txt"
renamed_old=()
renamed_new=()
if [ -f "$RENAMED_HOOKS_FILE" ]; then
  while IFS= read -r rline; do
    [[ "$rline" =~ ^# ]] && continue
    [[ -z "$rline" ]]    && continue
    _rold="${rline%% ->*}"
    _rnew="${rline##*-> }"
    renamed_old+=("$_rold")
    renamed_new+=("$_rnew")
  done < "$RENAMED_HOOKS_FILE"
fi

# Load intentional-changes allowlist
# Format: path | reason
intentional_paths=()
intentional_reasons=()
if [ -f "$INTENTIONAL_CHANGES_FILE" ]; then
  while IFS= read -r iline; do
    [[ "$iline" =~ ^# ]] && continue
    [[ -z "$iline"     ]] && continue
    _ipath="${iline%% |*}"
    _ipath="${_ipath%% }"   # trim trailing space
    _ireason="${iline##*| }"
    intentional_paths+=("$_ipath")
    intentional_reasons+=("$_ireason")
  done < "$INTENTIONAL_CHANGES_FILE"
fi

# Load removed-files allowlist
# Format: path | reason
# Lists baseline files that are deliberately no longer installed.
removed_paths=()
removed_reasons=()
if [ -f "$REMOVED_FILES_FILE" ]; then
  while IFS= read -r rline; do
    [[ "$rline" =~ ^# ]] && continue
    [[ -z "$rline"     ]] && continue
    _rpath="${rline%% |*}"
    _rpath="${_rpath%% }"   # trim trailing space
    _rreason="${rline##*| }"
    removed_paths+=("$_rpath")
    removed_reasons+=("$_rreason")
  done < "$REMOVED_FILES_FILE"
fi

# --------------------------------------------------------------------------
# Staleness check — intentional-changes.txt entries whose installed file
# now matches the baseline hash are stale (the change was reverted).
# --------------------------------------------------------------------------
echo "--- Intentional-changes staleness check ---"
_stale_found=false
for ii in "${!intentional_paths[@]}"; do
  _ipath="${intentional_paths[$ii]}"
  # Find baseline hash for this path
  _ibaseline_md5=""
  for bi in "${!baseline_paths[@]}"; do
    if [ "${baseline_paths[$bi]}" = "$_ipath" ]; then
      _ibaseline_md5="${baseline_md5s[$bi]}"
      break
    fi
  done
  [ -z "$_ibaseline_md5" ] && continue
  _iactual_path="${_ipath/#\~/$FAKE_HOME}"
  if [ -f "$_iactual_path" ]; then
    _iactual_md5=$(file_md5 "$_iactual_path")
    if [ "$_iactual_md5" = "$_ibaseline_md5" ]; then
      echo "  FAIL: stale entry in intentional-changes.txt: $_ipath"
      echo "        (installed hash matches baseline — remove this entry)"
      fail_count=$((fail_count + 1))
      fail_messages+=("STALE INTENTIONAL ENTRY: $_ipath")
      _stale_found=true
    fi
  fi
done
if ! $_stale_found; then
  echo "  (no stale entries)"
fi

# --------------------------------------------------------------------------
# Staleness check — removed-files.txt entries whose path IS present after
# install are stale (the file was restored but the allowlist was not cleaned up).
# --------------------------------------------------------------------------
echo ""
echo "--- Removed-files staleness check ---"
_removed_stale_found=false
for ri in "${!removed_paths[@]}"; do
  _rpath="${removed_paths[$ri]}"
  _ractual_path="${_rpath/#\~/$FAKE_HOME}"
  if [ -f "$_ractual_path" ]; then
    echo "  FAIL: stale entry in removed-files.txt: $_rpath"
    echo "        (file IS installed — remove this entry or stop installing it)"
    fail_count=$((fail_count + 1))
    fail_messages+=("STALE REMOVED ENTRY: $_rpath")
    _removed_stale_found=true
  fi
done
if ! $_removed_stale_found; then
  echo "  (no stale entries)"
fi

echo ""
echo "--- Non-hook files vs baseline ---"

for i in "${!baseline_paths[@]}"; do
  bpath="${baseline_paths[$i]}"
  bmd5="${baseline_md5s[$i]}"

  # Expand ~ to FAKE_HOME for the actual path
  actual_path="${bpath/#\~/$FAKE_HOME}"

  # Classify: hooks vs settings vs everything else
  # Note: keep the literal ~ here; bpath values come from the manifest as-is
  if [[ "$bpath" == "~/.claude/hooks/"* ]]; then
    # Hook file — handling depends on whether the file exists:
    #   EXISTS + md5 matches: "matched (unexpected)"
    #   EXISTS + md5 differs: "changed (expected)", no fail
    #   MISSING + in renamed-hooks.txt with replacement installed: "renamed (expected)", no fail
    #   MISSING + not in allowlist: FAIL
    if [ -f "$actual_path" ]; then
      installed_md5=$(file_md5 "$actual_path")
      if [ "$installed_md5" = "$bmd5" ]; then
        hook_reports+=("  matched (unexpected — was expected to change): $bpath")
      else
        hook_reports+=("  changed (expected): $bpath")
      fi
    else
      # File is missing — check renamed-hooks.txt allowlist
      basename_old="$(basename "$bpath")"
      _found_rename=false
      for ri in "${!renamed_old[@]}"; do
        if [ "${renamed_old[$ri]}" = "$basename_old" ]; then
          _replacement="${renamed_new[$ri]}"
          _replacement_path="${FAKE_HOME}/.claude/hooks/${_replacement}"
          if [ -x "$_replacement_path" ]; then
            hook_reports+=("  renamed (expected): $bpath -> ~/.claude/hooks/${_replacement}")
            _found_rename=true
          else
            hook_reports+=("  renamed but replacement missing/non-executable: $bpath -> ~/.claude/hooks/${_replacement}")
            echo "  FAIL: $bpath (renamed to ${_replacement} but replacement not installed)"
            fail_count=$((fail_count + 1))
            fail_messages+=("MISSING (replacement not found): $bpath -> ${_replacement}")
            _found_rename=true  # prevent double-failure
          fi
          break
        fi
      done
      if ! $_found_rename; then
        echo "  FAIL: $bpath (missing — not in renamed-hooks.txt)"
        fail_count=$((fail_count + 1))
        fail_messages+=("MISSING (not renamed): $bpath")
      fi
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

  # Regular file — must exist and md5 must match baseline, OR path must
  # appear in intentional-changes.txt with a non-empty reason.
  # If the file is absent, it passes only if listed in removed-files.txt.
  if [ ! -f "$actual_path" ]; then
    _found_removed=false
    for ri in "${!removed_paths[@]}"; do
      if [ "${removed_paths[$ri]}" = "$bpath" ]; then
        _rreason="${removed_reasons[$ri]}"
        if [ -n "$_rreason" ]; then
          echo "  ok (removed): $bpath"
          echo "        reason: $_rreason"
          pass_count=$((pass_count + 1))
          _found_removed=true
        fi
        break
      fi
    done
    if ! $_found_removed; then
      echo "  FAIL: $bpath (missing — not in removed-files.txt)"
      fail_count=$((fail_count + 1))
      fail_messages+=("MISSING: $bpath")
    fi
  else
    actual_md5=$(file_md5 "$actual_path")
    if [ "$actual_md5" = "$bmd5" ]; then
      echo "  ok: $bpath"
      pass_count=$((pass_count + 1))
    else
      # Hash mismatch — check intentional-changes.txt
      _found_intentional=false
      for ii in "${!intentional_paths[@]}"; do
        if [ "${intentional_paths[$ii]}" = "$bpath" ]; then
          _ireason="${intentional_reasons[$ii]}"
          if [ -n "$_ireason" ]; then
            echo "  ok (intentional): $bpath"
            echo "        reason: $_ireason"
            pass_count=$((pass_count + 1))
            _found_intentional=true
          fi
          break
        fi
      done
      if ! $_found_intentional; then
        echo "  FAIL: $bpath (md5 mismatch — not in intentional-changes.txt)"
        echo "        baseline: $bmd5"
        echo "        actual:   $actual_md5"
        fail_count=$((fail_count + 1))
        fail_messages+=("MD5 MISMATCH: $bpath")
      fi
    fi
  fi
done

# --------------------------------------------------------------------------
# Report hook files (expected-changed/renamed — not counted toward pass/fail
# unless already FAIL'd above for missing + not-in-allowlist cases)
# --------------------------------------------------------------------------
echo ""
echo "--- Hook files (expected-changed/renamed, not counted unless missing) ---"
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
# Command-path checks: every hook command registered in settings.json (Claude)
# and config.toml (Codex) must exist and be executable after install.
# This is the direct check that would have caught C1 (dead push-guard path).
# --------------------------------------------------------------------------
echo ""
echo "--- Settings command-path checks ---"

# Claude: parse command values from .claude/settings.json
# Matches lines of the form:  "command": "$HOME/..."
while IFS= read -r cmd_path; do
  expanded="${cmd_path/\$HOME/$FAKE_HOME}"
  if [ -x "$expanded" ]; then
    echo "  ok: $cmd_path"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: command not found or not executable after install: $cmd_path"
    fail_count=$((fail_count + 1))
    fail_messages+=("COMMAND NOT EXECUTABLE (claude): $cmd_path")
  fi
done < <(grep '"command"[[:space:]]*:' "${REPO_ROOT}/.claude/settings.json" \
           | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')

# Codex: run --codex --apply install into a separate temp HOME and check
# command paths from config.toml
CODEX_FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "$CODEX_FAKE_HOME"' EXIT
HOME="$CODEX_FAKE_HOME" bash "$INSTALL" --codex --apply > /dev/null 2>&1

echo ""
echo "--- Codex config.toml command-path checks ---"
while IFS= read -r cmd_path; do
  expanded="${cmd_path/\$HOME/$CODEX_FAKE_HOME}"
  if [ -x "$expanded" ]; then
    echo "  ok: $cmd_path"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: command not found or not executable after codex install: $cmd_path"
    fail_count=$((fail_count + 1))
    fail_messages+=("COMMAND NOT EXECUTABLE (codex): $cmd_path")
  fi
done < <(grep -E '^[[:space:]]*command[[:space:]]*=[[:space:]]*"' "${REPO_ROOT}/.codex/config.toml" \
           | sed -E 's/^[[:space:]]*command[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')

echo ""
echo "--- Codex content baseline checks ---"

BASELINE_CODEX="${REPO_ROOT}/tests/codex-baseline-manifest.txt"

if [ ! -f "$BASELINE_CODEX" ]; then
  echo "  FAIL: codex-baseline-manifest.txt missing"
  fail_count=$((fail_count + 1))
  fail_messages+=("MISSING: codex-baseline-manifest.txt")
else
  codex_baseline_paths=()
  codex_baseline_md5s=()

  while IFS= read -r line; do
    [[ "$line" =~ ^# ]] && continue
    [[ -z "$line"    ]] && continue
    bpath="${line%%  *}"
    bmd5="${line##*  }"
    codex_baseline_paths+=("$bpath")
    codex_baseline_md5s+=("$bmd5")
  done < "$BASELINE_CODEX"

  for i in "${!codex_baseline_paths[@]}"; do
    bpath="${codex_baseline_paths[$i]}"
    bmd5="${codex_baseline_md5s[$i]}"

    actual_path="${CODEX_FAKE_HOME}/${bpath#\~/}"

    if [ ! -f "$actual_path" ]; then
      _found_removed=false
      for ri in "${!removed_paths[@]}"; do
        if [ "${removed_paths[$ri]}" = "$bpath" ]; then
          _rreason="${removed_reasons[$ri]}"
          if [ -n "$_rreason" ]; then
            echo "  ok (removed): $bpath"
            echo "        reason: $_rreason"
            pass_count=$((pass_count + 1))
            _found_removed=true
          fi
          break
        fi
      done
      if ! $_found_removed; then
        echo "  FAIL: $bpath (missing — not in removed-files.txt)"
        fail_count=$((fail_count + 1))
        fail_messages+=("MISSING (codex): $bpath")
      fi
    else
      actual_md5=$(file_md5 "$actual_path")
      if [ "$actual_md5" = "$bmd5" ]; then
        echo "  ok: $bpath"
        pass_count=$((pass_count + 1))
      else
        _found_intentional=false
        for ii in "${!intentional_paths[@]}"; do
          if [ "${intentional_paths[$ii]}" = "$bpath" ]; then
            _ireason="${intentional_reasons[$ii]}"
            if [ -n "$_ireason" ]; then
              echo "  ok (intentional): $bpath"
              echo "        reason: $_ireason"
              pass_count=$((pass_count + 1))
              _found_intentional=true
            fi
            break
          fi
        done
        if ! $_found_intentional; then
          echo "  FAIL: $bpath (md5 mismatch — not in intentional-changes.txt)"
          echo "        baseline: $bmd5"
          echo "        actual:   $actual_md5"
          fail_count=$((fail_count + 1))
          fail_messages+=("MD5 MISMATCH (codex): $bpath")
        fi
      fi
    fi
  done

  # Part B — dynamic check for config.toml (not in manifest — HOME-expanded)
  _codex_toml_actual="${CODEX_FAKE_HOME}/.codex/config.toml"
  if [ ! -f "$_codex_toml_actual" ]; then
    echo "  FAIL: ~/.codex/config.toml (missing)"
    fail_count=$((fail_count + 1))
    fail_messages+=("MISSING (codex): ~/.codex/config.toml")
  else
    _expected_toml_md5=$(sed "s|\$HOME|${CODEX_FAKE_HOME}|g" "${REPO_ROOT}/.codex/config.toml" | \
      (command -v md5 &>/dev/null && md5 || md5sum | awk '{print $1}'))
    _actual_toml_md5=$(file_md5 "$_codex_toml_actual")
    if [ "$_actual_toml_md5" = "$_expected_toml_md5" ]; then
      echo "  ok (dynamic): ~/.codex/config.toml (\$HOME expansion correct)"
      pass_count=$((pass_count + 1))
    else
      echo "  FAIL: ~/.codex/config.toml (config.toml md5 mismatch)"
      echo "        expected (dynamic): $_expected_toml_md5"
      echo "        actual:             $_actual_toml_md5"
      fail_count=$((fail_count + 1))
      fail_messages+=("MD5 MISMATCH (codex): ~/.codex/config.toml")
    fi
  fi
fi

# --------------------------------------------------------------------------
# Orphan scripts/ cleanup tests
#
# Case A: a decoy ~/.claude/skills/scripts/ directory (no SKILL.md) must be
#         removed by the installer.
# Case B: a ~/.claude/skills/scripts/ directory that CONTAINS a SKILL.md must
#         be left alone (it is a real user skill named "scripts").
# --------------------------------------------------------------------------
echo ""
echo "--- Orphan scripts/ cleanup tests ---"

# Case A — orphan removed
ORPHAN_HOME_A="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "$CODEX_FAKE_HOME" "$ORPHAN_HOME_A"' EXIT
mkdir -p "${ORPHAN_HOME_A}/.claude/skills/scripts"
printf 'dummy orphan file\n' > "${ORPHAN_HOME_A}/.claude/skills/scripts/hitl-loop.template.sh"
HOME="$ORPHAN_HOME_A" bash "$INSTALL" --claude > /dev/null 2>&1
if [ -d "${ORPHAN_HOME_A}/.claude/skills/scripts" ]; then
  echo "FAIL orphan-scripts-removed (orphan ~/.claude/skills/scripts/ was not removed)"
  fail_count=$((fail_count + 1))
  fail_messages+=("ORPHAN NOT REMOVED: ~/.claude/skills/scripts/")
else
  echo "PASS orphan-scripts-removed"
  pass_count=$((pass_count + 1))
fi

# Case B — real skill (has SKILL.md) preserved
ORPHAN_HOME_B="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "$CODEX_FAKE_HOME" "$ORPHAN_HOME_A" "$ORPHAN_HOME_B"' EXIT
mkdir -p "${ORPHAN_HOME_B}/.claude/skills/scripts"
printf 'name: scripts\n' > "${ORPHAN_HOME_B}/.claude/skills/scripts/SKILL.md"
HOME="$ORPHAN_HOME_B" bash "$INSTALL" --claude > /dev/null 2>&1
if [ -f "${ORPHAN_HOME_B}/.claude/skills/scripts/SKILL.md" ]; then
  echo "PASS orphan-scripts-guard-preserved"
  pass_count=$((pass_count + 1))
else
  echo "FAIL orphan-scripts-guard-preserved (SKILL.md was removed — real user skill must be preserved)"
  fail_count=$((fail_count + 1))
  fail_messages+=("REAL SKILL REMOVED: ~/.claude/skills/scripts/")
fi

# --------------------------------------------------------------------------
# Ledger hook exclusion tests
#
# Case 1: Claude install must NOT include ledger-*.sh (Codex-only detective
#         enforcement; not registered in Claude's settings.json).
# Case 2: Active (non-ledger) hooks must exist and be executable.
# Case 3: Codex install must include all three ledger-*.sh hooks.
# Case 4: Cleanup — a pre-seeded ledger hook must be removed by Claude install.
# --------------------------------------------------------------------------
echo ""
echo "--- Ledger hook exclusion tests ---"

# Case 1: no ledger hooks in Claude install
_ledger_found=false
for _lf in "${FAKE_HOME}/.claude/hooks/ledger-"*.sh; do
  [ -e "$_lf" ] || continue
  _ledger_found=true
  break
done
if $_ledger_found; then
  echo "FAIL ledger-excluded-from-claude (ledger-*.sh found in ~/.claude/hooks/)"
  fail_count=$((fail_count + 1))
  fail_messages+=("LEDGER HOOKS FOUND IN CLAUDE INSTALL")
else
  echo "PASS ledger-excluded-from-claude"
  pass_count=$((pass_count + 1))
fi

# Case 2: active hooks installed and executable in Claude install
for _hook in block-push.sh enforce-delegation.sh enforce-commit-ownership.sh; do
  _hp="${FAKE_HOME}/.claude/hooks/${_hook}"
  if [ -x "$_hp" ]; then
    echo "PASS active-hook-installed-${_hook}"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL active-hook-installed-${_hook} (${_hook} missing or not executable)"
    fail_count=$((fail_count + 1))
    fail_messages+=("ACTIVE HOOK NOT EXECUTABLE: ${_hook}")
  fi
done

# Case 3: Codex install includes all ledger-*.sh hooks
for _lhook in ledger-record.sh ledger-close.sh ledger-report.sh; do
  _lp="${CODEX_FAKE_HOME}/.codex/hooks/${_lhook}"
  if [ -x "$_lp" ]; then
    echo "PASS ledger-in-codex-${_lhook}"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL ledger-in-codex-${_lhook} (${_lhook} missing or not executable in Codex install)"
    fail_count=$((fail_count + 1))
    fail_messages+=("LEDGER HOOK NOT IN CODEX INSTALL: ${_lhook}")
  fi
done

# Case 4: cleanup — a pre-seeded ledger hook must be removed by Claude install
CLEANUP_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "$CODEX_FAKE_HOME" "$ORPHAN_HOME_A" "$ORPHAN_HOME_B" "$CLEANUP_HOME"' EXIT
mkdir -p "${CLEANUP_HOME}/.claude/hooks"
printf '#!/usr/bin/env bash\n# stale ledger stub\n' > "${CLEANUP_HOME}/.claude/hooks/ledger-record.sh"
HOME="$CLEANUP_HOME" bash "$INSTALL" --claude > /dev/null 2>&1
if [ -e "${CLEANUP_HOME}/.claude/hooks/ledger-record.sh" ]; then
  echo "FAIL ledger-cleanup (pre-seeded ledger-record.sh was not removed by Claude install)"
  fail_count=$((fail_count + 1))
  fail_messages+=("LEDGER CLEANUP FAILED: ledger-record.sh still present after Claude install")
else
  echo "PASS ledger-cleanup"
  pass_count=$((pass_count + 1))
fi

# --------------------------------------------------------------------------
# Superseded-command cleanup tests
#
# full-pipeline.md is no longer installed (superseded by full-pipeline-cycle).
# A user who ran an older install may still have it at ~/.claude/commands/.
# The installer must remove it.
# --------------------------------------------------------------------------
echo ""
echo "--- Superseded-command cleanup tests ---"

# Pre-seed ~/.claude/commands/full-pipeline.md, run install, verify it is gone.
SUPERSEDED_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "$CODEX_FAKE_HOME" "$ORPHAN_HOME_A" "$ORPHAN_HOME_B" "$CLEANUP_HOME" "$SUPERSEDED_HOME"' EXIT
mkdir -p "${SUPERSEDED_HOME}/.claude/commands"
printf '# stale full-pipeline stub\n' > "${SUPERSEDED_HOME}/.claude/commands/full-pipeline.md"
HOME="$SUPERSEDED_HOME" bash "$INSTALL" --claude > /dev/null 2>&1
if [ -e "${SUPERSEDED_HOME}/.claude/commands/full-pipeline.md" ]; then
  echo "FAIL superseded-full-pipeline-removed (pre-seeded full-pipeline.md was not removed by Claude install)"
  fail_count=$((fail_count + 1))
  fail_messages+=("SUPERSEDED COMMAND NOT REMOVED: ~/.claude/commands/full-pipeline.md still present after Claude install")
else
  echo "PASS superseded-full-pipeline-removed"
  pass_count=$((pass_count + 1))
fi

# --------------------------------------------------------------------------
# Adapter binding checks
#
# The installer must bind the RIGHT platform adapter at install time.
# If the wrong adapter is bound, hook_caller returns "unknown" for every
# call and all three guards become no-ops — so this must fail loudly.
#
# Claude install: ~/.claude/hooks/lib/adapter.sh ≡ adapter-claude.sh
#                                                ≢ adapter-codex.sh
# Codex install:  ~/.codex/hooks/lib/adapter.sh  ≡ adapter-codex.sh
#                                                ≢ adapter-claude.sh
# --------------------------------------------------------------------------
echo ""
echo "--- Adapter binding checks ---"

_adapter_claude_src="${REPO_ROOT}/.agents/hooks/lib/adapter-claude.sh"
_adapter_codex_src="${REPO_ROOT}/.agents/hooks/lib/adapter-codex.sh"

_claude_adapter="${FAKE_HOME}/.claude/hooks/lib/adapter.sh"

if cmp -s "$_claude_adapter" "$_adapter_claude_src"; then
  echo "PASS claude-adapter-positive (adapter.sh matches adapter-claude.sh)"
  pass_count=$((pass_count + 1))
else
  echo "FAIL claude-adapter-positive (adapter.sh does NOT match adapter-claude.sh)"
  fail_count=$((fail_count + 1))
  fail_messages+=("ADAPTER MISMATCH (claude): adapter.sh != adapter-claude.sh")
fi

if ! cmp -s "$_claude_adapter" "$_adapter_codex_src"; then
  echo "PASS claude-adapter-negative (adapter.sh is not adapter-codex.sh)"
  pass_count=$((pass_count + 1))
else
  echo "FAIL claude-adapter-negative (adapter.sh is identical to adapter-codex.sh — wrong adapter bound)"
  fail_count=$((fail_count + 1))
  fail_messages+=("ADAPTER WRONG (claude): adapter.sh is adapter-codex.sh")
fi

_codex_adapter="${CODEX_FAKE_HOME}/.codex/hooks/lib/adapter.sh"

if cmp -s "$_codex_adapter" "$_adapter_codex_src"; then
  echo "PASS codex-adapter-positive (adapter.sh matches adapter-codex.sh)"
  pass_count=$((pass_count + 1))
else
  echo "FAIL codex-adapter-positive (adapter.sh does NOT match adapter-codex.sh)"
  fail_count=$((fail_count + 1))
  fail_messages+=("ADAPTER MISMATCH (codex): adapter.sh != adapter-codex.sh")
fi

if ! cmp -s "$_codex_adapter" "$_adapter_claude_src"; then
  echo "PASS codex-adapter-negative (adapter.sh is not adapter-claude.sh)"
  pass_count=$((pass_count + 1))
else
  echo "FAIL codex-adapter-negative (adapter.sh is identical to adapter-claude.sh — wrong adapter bound)"
  fail_count=$((fail_count + 1))
  fail_messages+=("ADAPTER WRONG (codex): adapter.sh is adapter-claude.sh")
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "--- Summary ---"
echo "  ${pass_count} files/checks passed"
echo "  ${#hook_reports[@]} hook entries (expected-changed/renamed, not counted)"
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
