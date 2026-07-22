#!/usr/bin/env bash
# tests/test-codex-transform.sh — verify the Codex slash→dollar invocation-syntax
# transform handles adjacent slash-commands (I5 regression).
#
# The sed expression is applied twice so that two commands separated by a single
# boundary character are both transformed. With only one pass, the second command
# in "run /plan /build now" would remain as "/build".
#
# Usage: bash tests/test-codex-transform.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0

# ---------------------------------------------------------------------------
# Rebuild the transform expression the same way install.sh does.
# ---------------------------------------------------------------------------
build_expr() {
  local names_alt
  names_alt=$(for f in "$REPO_ROOT/.agents/workflows/"*.md; do
    name="$(basename "$f" .md)"
    printf '%d %s\n' "${#name}" "$name"
  done | sort -rn | awk '{print $2}' | tr '\n' '|' | sed 's/|$//')
  printf '%s' "s#(^|[^[:alnum:]/])/($names_alt)([^[:alnum:]-]|\$)#\1\$\2\3#g"
}

EXPR=$(build_expr)

# Apply expression twice (mirrors the double-pass in codex_transform_file).
transform() {
  printf '%s' "$1" | sed -E "$EXPR" | sed -E "$EXPR"
}

check() {
  local label="$1" input="$2" expected="$3"
  local actual
  actual=$(transform "$input")
  if [ "$actual" = "$expected" ]; then
    echo "PASS $label"
    pass=$((pass + 1))
  else
    echo "FAIL $label"
    echo "  input:    $input"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Adjacent slash-commands (I5 regression cases)
# ---------------------------------------------------------------------------

# Two adjacent commands separated by a space — both must transform.
check "adjacent-space" \
  "run /plan /build now" \
  "run \$plan \$build now"

# Two adjacent commands separated by a comma — both must transform.
check "adjacent-comma" \
  "see /spec,/ship end" \
  "see \$spec,\$ship end"

# Two adjacent commands at line start — both must transform.
check "adjacent-line-start" \
  "/spec /plan" \
  "\$spec \$plan"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
total=$((pass + fail))
echo "${pass}/${total} passed"

[ "$fail" -eq 0 ] && exit 0 || exit 1
