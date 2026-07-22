#!/usr/bin/env bash
# tests/test-agent-assembly.sh — verify agent assembly from header + shared body files
#
# Strategy:
#   Claude agents: assembled output must be byte-identical to the old .claude/agents/*.md
#   files, EXCEPT implementer where exactly 2 "Opus" -> "the orchestrator" substitutions
#   are the only permitted differences.
#
#   Codex agents: assembled output is verified as valid TOML with correct key field values.
#   Byte-identical comparison against old Codex files is not attempted because the old files
#   used """ delimiters while the new assembly uses ''' (TOML literal strings), and
#   pre-existing body differences exist between platforms for 5 of 6 agents.
#
# Usage: bash tests/test-agent-assembly.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN_CLAUDE="$REPO_ROOT/tests/fixtures/golden-agents/claude"

pass=0
fail=0

_pass() { echo "PASS $1"; pass=$((pass + 1)); }
_fail() { echo "FAIL $1: ${2:-}"; fail=$((fail + 1)); }

# --------------------------------------------------------------------------
# Helper: get the Claude output filename for a given agent name
# --------------------------------------------------------------------------
claude_out_name() {
  case "$1" in
    explore) echo "Explore.md" ;;
    *)       echo "${1}.md" ;;
  esac
}

# Helper: get expected Codex model for a given agent name
codex_expected_model() {
  case "$1" in
    reader|explore)               echo "gpt-5.6-luna" ;;
    implementer|test-engineer)    echo "gpt-5.6-terra" ;;
    code-reviewer|security-auditor) echo "gpt-5.6-sol" ;;
    *) echo "unknown" ;;
  esac
}

# --------------------------------------------------------------------------
# Assemble all agents into a temp dir
# --------------------------------------------------------------------------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/claude" "$TMPDIR/codex"

# Guard: verify no shared body contains '''
for body in "$REPO_ROOT/.agents/agents/"*.md; do
  if grep -q "'''" "$body" 2>/dev/null; then
    _fail "guard-toml-literal" "$body contains ''' which would break TOML literal strings"
  fi
done

# Claude assembly
for name in explore reader implementer test-engineer code-reviewer security-auditor; do
  header="$REPO_ROOT/.claude/agents/${name}.header.md"
  body="$REPO_ROOT/.agents/agents/${name}.md"
  out_name="$(claude_out_name "$name")"
  dest="$TMPDIR/claude/${out_name}"

  if [ ! -f "$header" ]; then
    _fail "claude-${name}-assemble" "header not found: $header"
    continue
  fi
  if [ ! -f "$body" ]; then
    _fail "claude-${name}-assemble" "body not found: $body"
    continue
  fi

  cat "$header" "$body" > "$dest"
done

# Codex assembly
for name in reader explore implementer test-engineer code-reviewer security-auditor; do
  header="$REPO_ROOT/.codex/agents/${name}.header.toml"
  body="$REPO_ROOT/.agents/agents/${name}.md"
  dest="$TMPDIR/codex/${name}.toml"

  if [ ! -f "$header" ]; then
    _fail "codex-${name}-assemble" "header not found: $header"
    continue
  fi
  if [ ! -f "$body" ]; then
    _fail "codex-${name}-assemble" "body not found: $body"
    continue
  fi

  { cat "$header"
    printf "developer_instructions = '''\n"
    cat "$body"
    printf "'''\n"
  } > "$dest"
done

# --------------------------------------------------------------------------
# Claude: byte-identical comparison against old agent files
# --------------------------------------------------------------------------
echo "--- Claude agent assembly ---"

# 5 agents that must be exactly identical to old files
for name in explore reader test-engineer code-reviewer security-auditor; do
  out_name="$(claude_out_name "$name")"
  assembled="$TMPDIR/claude/${out_name}"
  golden="$GOLDEN_CLAUDE/${out_name}"

  if [ ! -f "$golden" ]; then
    _fail "claude-${name}" "golden file missing: $golden"
    continue
  fi
  if [ ! -f "$assembled" ]; then
    _fail "claude-${name}" "assembled file missing"
    continue
  fi

  if diff -q "$golden" "$assembled" > /dev/null 2>&1; then
    _pass "claude-${name} (byte-identical to golden)"
  else
    _fail "claude-${name}" "unexpected diff vs golden"
    diff "$golden" "$assembled" | head -15
  fi
done

# implementer: ONLY the two "Opus" -> "the orchestrator" body lines are permitted to differ
{
  old="$GOLDEN_CLAUDE/implementer.md"
  assembled="$TMPDIR/claude/implementer.md"

  if [ ! -f "$old" ]; then
    _fail "claude-implementer" "golden file missing"
  elif [ ! -f "$assembled" ]; then
    _fail "claude-implementer" "assembled file missing"
  else
    diff_out=$(diff "$old" "$assembled" 2>/dev/null || true)

    # Count total differing lines (lines starting with < or >)
    diff_lines=$(printf '%s\n' "$diff_out" | grep -c '^[<>]' || true)

    # The permitted diff has exactly 4 diff lines (2 old + 2 new)
    expected_old1='- Flag anything that Opus should review or that deviated from the plan'
    expected_new1='- Flag anything that the orchestrator should review or that deviated from the plan'
    expected_old2='back to Opus with a clear description of what is blocking you.'
    expected_new2='back to the orchestrator with a clear description of what is blocking you.'

    ok=true

    if [ "$diff_lines" -ne 4 ]; then
      ok=false
      echo "  claude-implementer: expected 4 diff lines (2 old + 2 new), got $diff_lines"
    fi

    if ! printf '%s\n' "$diff_out" | grep -qF "< $expected_old1"; then ok=false; echo "  missing expected old line 1"; fi
    if ! printf '%s\n' "$diff_out" | grep -qF "> $expected_new1"; then ok=false; echo "  missing expected new line 1"; fi
    if ! printf '%s\n' "$diff_out" | grep -qF "< $expected_old2"; then ok=false; echo "  missing expected old line 2"; fi
    if ! printf '%s\n' "$diff_out" | grep -qF "> $expected_new2"; then ok=false; echo "  missing expected new line 2"; fi

    if $ok; then
      _pass "claude-implementer (only 2 permitted Opus->orchestrator diffs)"
    else
      _fail "claude-implementer" "unexpected diff content"
      printf '%s\n' "$diff_out" | head -20
    fi
  fi
}

# --------------------------------------------------------------------------
# Codex: TOML validity + key field checks
# --------------------------------------------------------------------------
echo ""
echo "--- Codex agent assembly (TOML validation + key fields) ---"

for name in reader explore implementer test-engineer code-reviewer security-auditor; do
  assembled="$TMPDIR/codex/${name}.toml"

  if [ ! -f "$assembled" ]; then
    _fail "codex-${name}" "assembled file missing"
    continue
  fi

  expected_model="$(codex_expected_model "$name")"

  parse_result=$(python3 - "$assembled" "$name" "$expected_model" <<'PYEOF'
import tomllib, sys

fpath, expected_name, expected_model = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(fpath, 'rb') as f:
        data = tomllib.load(f)
    errors = []
    if data.get('name') != expected_name:
        errors.append(f'name: expected {expected_name!r}, got {data.get("name")!r}')
    if data.get('model') != expected_model:
        errors.append(f'model: expected {expected_model!r}, got {data.get("model")!r}')
    if 'developer_instructions' not in data:
        errors.append('developer_instructions key missing')
    elif not data['developer_instructions'].strip():
        errors.append('developer_instructions is empty')
    print('ERRORS: ' + '; '.join(errors) if errors else 'OK')
except Exception as e:
    print(f'PARSE_ERROR: {e}')
PYEOF
  )

  if [ "$parse_result" = "OK" ]; then
    _pass "codex-${name} (valid TOML, name=${name}, model=${expected_model})"
  else
    _fail "codex-${name}" "$parse_result"
  fi
done

# --------------------------------------------------------------------------
# Codex implementer: developer_instructions must match shared body exactly
# (implementer is the one agent where Claude and Codex bodies were already aligned)
# --------------------------------------------------------------------------
{
  assembled="$TMPDIR/codex/implementer.toml"
  body="$REPO_ROOT/.agents/agents/implementer.md"

  if [ -f "$assembled" ] && [ -f "$body" ]; then
    body_content="$(cat "$body")"
    extracted=$(python3 - "$assembled" <<'PYEOF'
import tomllib, sys
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
print(data.get('developer_instructions', ''), end='')
PYEOF
    )

    if [ "$extracted" = "$body_content" ]; then
      _pass "codex-implementer-body (developer_instructions matches shared body)"
    else
      _fail "codex-implementer-body" "developer_instructions content mismatch"
      diff <(printf '%s' "$body_content") <(printf '%s' "$extracted") | head -10
    fi
  fi
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
total=$((pass + fail))
echo "$pass/$total passed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
