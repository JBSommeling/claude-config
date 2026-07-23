#!/usr/bin/env bash
# tests/test-platform-neutrality.sh — enforce platform-neutrality rules
#
# Rule 1: .agents/** content that reaches the model must be platform-neutral.
#         Forbidden in agent bodies, workflows, and skills:
#           Claude-specific: Opus, Sonnet, Haiku, CLAUDE.md, ~/.claude, .claude/,
#                            MultiEdit, NotebookEdit
#           Codex-specific:  gpt-5.6, ~/.codex, .codex/, AGENTS.md, apply_patch
#         Note: "Claude Code" as a platform name used neutrally alongside "Codex"
#         is acceptable. What matters is banning model-tier names and paths.
#         Forbidden in hook deny messages (SUFFIX= and hook_deny lines):
#           Opus, Sonnet, Haiku, CLAUDE.md, ~/.claude
#
# Rule 2: .claude/** must not reference Codex.
#         Forbidden: codex (case-insensitive), gpt-5.6, ~/.codex, .codex/,
#                    AGENTS.md, apply_patch
#
# Rule 3: .codex/** must not reference Claude via specific paths or tool names.
#         Forbidden: ~/.claude, .claude/, CLAUDE.md, MultiEdit, NotebookEdit
#         "Claude Code" in provenance notes (AGENTS.md) is acceptable — use
#         judgement; this test checks paths and tool names only.
#
# Exempt from all rules: docs/adr/, README.md, tests/, install.sh
# Also exempt: .agents/hooks/lib/ (platform adapter files by design)
# Also exempt: CLAUDE_BYPASS_* env var names (real on both platforms)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0

_pass() { echo "PASS $1"; pass=$((pass + 1)); }
_fail() { echo "FAIL $1"; echo "       ${2:-}"; fail=$((fail + 1)); }

# _grep_clean LABEL PATTERN PATHS...
# Runs grep -rn across PATHS; FAILs if any match is found.
_grep_clean() {
  local label="$1" pattern="$2"
  shift 2
  local hits
  hits=$(grep -rn -E "$pattern" "$@" 2>/dev/null || true)
  if [ -z "$hits" ]; then
    _pass "$label"
  else
    _fail "$label" "$(printf '%s\n' "$hits" | head -5)"
  fi
}

# _deny_grep_clean LABEL PATTERN FILE...
# Extracts only hook_deny and SUFFIX= lines from FILES, then checks the pattern.
_deny_grep_clean() {
  local label="$1" pattern="$2"
  shift 2
  local deny_lines hits
  deny_lines=$(grep -E '(hook_deny|SUFFIX=)' "$@" 2>/dev/null || true)
  hits=$(printf '%s\n' "$deny_lines" | grep -E "$pattern" || true)
  if [ -z "$hits" ]; then
    _pass "$label"
  else
    _fail "$label" "$(printf '%s\n' "$hits" | head -5)"
  fi
}

# ---------------------------------------------------------------------------
# Rule 1 — .agents/** (excluding hooks/lib/)
# ---------------------------------------------------------------------------
echo "--- Rule 1a: agent bodies ---"

# Forbidden model-tier names and platform-specific paths/tools.
# Note: "Claude Code" as a platform name used neutrally alongside "Codex" is
# acceptable (e.g. ship.md explains the subagent_type mechanism for each platform).
# The dangerous contamination is model-tier names (Opus/Sonnet/Haiku) and
# Claude-specific paths/instructions files, not the platform name itself.
CLAUDE_BANNED='Opus|Sonnet|Haiku|CLAUDE\.md|~/\.claude|\.claude/|MultiEdit|NotebookEdit'
CODEX_BANNED='gpt-5\.6|~/\.codex|\.codex/|AGENTS\.md|apply_patch'

_grep_clean "rule1-agents-no-claude-terms" \
  "$CLAUDE_BANNED" \
  "$REPO/.agents/agents/"

_grep_clean "rule1-agents-no-codex-terms" \
  "$CODEX_BANNED" \
  "$REPO/.agents/agents/"

echo ""
echo "--- Rule 1b: workflows ---"

_grep_clean "rule1-workflows-no-claude-terms" \
  "$CLAUDE_BANNED" \
  "$REPO/.agents/workflows/"

_grep_clean "rule1-workflows-no-codex-terms" \
  "$CODEX_BANNED" \
  "$REPO/.agents/workflows/"

echo ""
echo "--- Rule 1c: skills ---"

_grep_clean "rule1-skills-no-claude-terms" \
  "$CLAUDE_BANNED" \
  "$REPO/.agents/skills/"

_grep_clean "rule1-skills-no-codex-terms" \
  "$CODEX_BANNED" \
  "$REPO/.agents/skills/"

echo ""
echo "--- Rule 1d: hook deny messages (not lib/) ---"

HOOK_DENY_CLAUDE='Opus|Sonnet|Haiku|CLAUDE\.md|~/\.claude'

for hook in "$REPO/.agents/hooks/"*.sh; do
  name="$(basename "$hook")"
  _deny_grep_clean "rule1-hook-deny-${name}" \
    "$HOOK_DENY_CLAUDE" \
    "$hook"
done

# ---------------------------------------------------------------------------
# Rule 2 — .claude/** must not reference Codex
# ---------------------------------------------------------------------------
echo ""
echo "--- Rule 2: .claude/** no Codex references ---"

CODEX_REF='[Cc]odex|gpt-5\.6|~/\.codex|\.codex/|AGENTS\.md|apply_patch'

_grep_clean "rule2-claude-no-codex" \
  "$CODEX_REF" \
  "$REPO/.claude/"

# ---------------------------------------------------------------------------
# Rule 3 — .codex/** must not reference Claude paths/tool names
# ---------------------------------------------------------------------------
echo ""
echo "--- Rule 3: .codex/** no Claude-specific paths or tool names ---"

CLAUDE_PATHS='~/\.claude|\.claude/|CLAUDE\.md|MultiEdit|NotebookEdit'

_grep_clean "rule3-codex-no-claude-paths" \
  "$CLAUDE_PATHS" \
  "$REPO/.codex/"

# ---------------------------------------------------------------------------
# Rule 4 — Codex install: invocation-syntax transform is applied
#
# 4a: No installed Codex workflow or skill file may contain a /NAME slash-command
#     reference for any workflow name (the transform must have rewritten them all).
# 4b: The Claude install must still contain /NAME references in commands/skills
#     (the transform must not leak into the Claude install path).
# ---------------------------------------------------------------------------
echo ""
echo "--- Rule 4: Codex invocation-syntax transform (install smoke test) ---"

# Build names_alt (longest-first) — mirrors the logic in install.sh
_NAMES_ALT=$(for f in "$REPO/.agents/workflows/"*.md; do
  name="$(basename "$f" .md)"
  printf '%d %s\n' "${#name}" "$name"
done | sort -rn | awk '{print $2}' | tr '\n' '|' | sed 's/|$//')

# Slash-command presence pattern (same anchoring as the sed transform).
# $) in double quotes: $ followed by ) is not a valid shell expansion → literal $.
# grep -E sees $ as end-of-line inside the alternation group.
_SLASH_PATTERN="(^|[^[:alnum:]/])/($_NAMES_ALT)([^[:alnum:]-]|$)"

# Run installs into isolated temp homes
_CODEX_HOME=$(mktemp -d)
_CLAUDE_HOME=$(mktemp -d)
trap 'rm -rf "$_CODEX_HOME" "$_CLAUDE_HOME"' EXIT

HOME="$_CODEX_HOME" bash "$REPO/install.sh" --codex --apply >/dev/null 2>&1
HOME="$_CLAUDE_HOME" bash "$REPO/install.sh" --claude >/dev/null 2>&1

# Rule 4a: Codex install must have zero /NAME refs in skills (includes copied workflows)
_codex_hits=$(find "$_CODEX_HOME/.agents/skills/" -name "*.md" -type f -print0 2>/dev/null | \
  xargs -0 grep -l -E "$_SLASH_PATTERN" 2>/dev/null || true)

if [ -z "$_codex_hits" ]; then
  _pass "rule4a-codex-no-slash-commands"
else
  _fail "rule4a-codex-no-slash-commands" \
    "Files still contain /name refs after Codex install: $(printf '%s\n' "$_codex_hits" | head -3)"
fi

# Rule 4b: Claude install must still have /NAME refs in commands/ and skills/
# (verifies the transform does not affect the Claude install path)
_claude_hits=$(find "$_CLAUDE_HOME/.claude/" \( -path "*/commands/*.md" -o -path "*/skills/*/*.md" \) \
  -type f -print0 2>/dev/null | \
  xargs -0 grep -l -E "$_SLASH_PATTERN" 2>/dev/null || true)

if [ -n "$_claude_hits" ]; then
  _pass "rule4b-claude-retains-slash-commands"
else
  _fail "rule4b-claude-retains-slash-commands" \
    "Claude install lost /name slash-command refs — transform may have leaked into Claude path"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
total=$((pass + fail))
echo "$pass/$total passed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
