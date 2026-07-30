#!/usr/bin/env bash
# tests/test-install-coverage.sh — assert install.sh actually installs each source file.
# No hashes, no manifests. Source files are enumerated dynamically so adding a new
# workflow/skill/hook is covered automatically with zero bookkeeping.

set -uo pipefail

# nullglob: without this, a glob that matches nothing expands to its own literal
# pattern string. The loop body then executes once on a nonexistent path, the
# counter becomes 1, and the anti-vacuity guard (count -eq 0) can never fire.
# With nullglob, an unmatched glob expands to nothing and the loop is skipped.
shopt -s nullglob

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0

_pass() { echo "PASS $1"; pass=$((pass + 1)); }
_fail() { echo "FAIL $1 — $2"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Setup — run install into two throwaway HOME dirs
# ---------------------------------------------------------------------------
CLAUDE_HOME="$(mktemp -d)"
CODEX_HOME="$(mktemp -d)"
trap 'rm -rf "$CLAUDE_HOME" "$CODEX_HOME"' EXIT

HOME="$CLAUDE_HOME" bash "$REPO_ROOT/install.sh" --claude >/dev/null 2>&1
HOME="$CODEX_HOME" bash "$REPO_ROOT/install.sh" --codex --apply >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Collision map — mirrors install.sh logic (lines ~386-393):
# if a real skill dir shares a workflow's basename, append -workflow.
# ---------------------------------------------------------------------------
collision_names=""
for _sd in "$REPO_ROOT/.agents/skills/"/*/; do
  collision_names="${collision_names} $(basename "${_sd%/}")"
done

workflow_skill_name() {
  local base="$1" _cn
  for _cn in $collision_names; do
    if [ "$_cn" = "$base" ]; then echo "${base}-workflow"; return; fi
  done
  echo "$base"
}

# ---------------------------------------------------------------------------
# Check 1: Workflows -> Claude commands (~/.claude/commands/<basename>.md)
# ---------------------------------------------------------------------------
wf_count=0; wf_fail=0
for f in "$REPO_ROOT/.agents/workflows/"*.md; do
  wf_count=$((wf_count + 1))
  dest="$CLAUDE_HOME/.claude/commands/$(basename "$f")"
  [ -f "$dest" ] || { echo "  missing: $dest"; wf_fail=$((wf_fail + 1)); }
done
if   [ "$wf_count" -eq 0 ]; then _fail "workflows-to-claude-commands" "enumeration found nothing — check proves nothing"
elif [ "$wf_fail"  -eq 0 ]; then _pass "workflows-to-claude-commands ($wf_count checked)"
else _fail "workflows-to-claude-commands" "$wf_fail of $wf_count missing"; fi

# ---------------------------------------------------------------------------
# Check 2: Workflows -> Codex skills (~/.agents/skills/<name>/SKILL.md)
# ---------------------------------------------------------------------------
wf2_fail=0
for f in "$REPO_ROOT/.agents/workflows/"*.md; do
  base="$(basename "$f" .md)"
  sname="$(workflow_skill_name "$base")"
  dest="$CODEX_HOME/.agents/skills/$sname/SKILL.md"
  [ -f "$dest" ] || { echo "  missing: $dest"; wf2_fail=$((wf2_fail + 1)); }
done
if   [ "$wf_count" -eq 0 ]; then _fail "workflows-to-codex-skills" "enumeration found nothing — check proves nothing"
elif [ "$wf2_fail" -eq 0 ]; then _pass "workflows-to-codex-skills ($wf_count checked)"
else _fail "workflows-to-codex-skills" "$wf2_fail of $wf_count missing"; fi

# ---------------------------------------------------------------------------
# Check 3: Skills -> both platforms
#   Claude: ~/.claude/skills/<name>/SKILL.md
#   Codex:  ~/.agents/skills/<name>/SKILL.md
# ---------------------------------------------------------------------------
sk_count=0; sk_fail=0
for skill_dir in "$REPO_ROOT/.agents/skills/"/*/; do
  [ -f "${skill_dir}SKILL.md" ] || continue
  sk_count=$((sk_count + 1))
  name="$(basename "${skill_dir%/}")"
  for dest in "$CLAUDE_HOME/.claude/skills/$name/SKILL.md" \
               "$CODEX_HOME/.agents/skills/$name/SKILL.md"; do
    [ -f "$dest" ] || { echo "  missing: $dest"; sk_fail=$((sk_fail + 1)); }
  done
done
if   [ "$sk_count" -eq 0 ]; then _fail "skills-both-platforms" "enumeration found nothing — check proves nothing"
elif [ "$sk_fail"  -eq 0 ]; then _pass "skills-both-platforms ($sk_count checked)"
else _fail "skills-both-platforms" "$sk_fail missing path(s) across $sk_count skills"; fi

# ---------------------------------------------------------------------------
# Check 4: Agents -> Claude (~/.claude/agents/<name>.md or Explore.md)
# install.sh assembles from .claude/agents/*.header.md — only bodies that have
# a matching header are installed; skip bodies without one.
# ---------------------------------------------------------------------------
ag_count=0; ag_fail=0
for body in "$REPO_ROOT/.agents/agents/"*.md; do
  name="$(basename "$body" .md)"
  [ -f "$REPO_ROOT/.claude/agents/${name}.header.md" ] || continue
  ag_count=$((ag_count + 1))
  case "$name" in explore) out="Explore.md" ;; *) out="${name}.md" ;; esac
  dest="$CLAUDE_HOME/.claude/agents/$out"
  [ -f "$dest" ] || { echo "  missing: $dest"; ag_fail=$((ag_fail + 1)); }
done
if   [ "$ag_count" -eq 0 ]; then _fail "agents-claude" "enumeration found nothing — check proves nothing"
elif [ "$ag_fail"  -eq 0 ]; then _pass "agents-claude ($ag_count checked)"
else _fail "agents-claude" "$ag_fail of $ag_count missing"; fi

# ---------------------------------------------------------------------------
# Check 5: Hooks installed AND executable in ~/.claude/hooks/
# ledger-*.sh are Codex-only and skipped by install.sh — mirror that here.
#
# Coverage note: this verifies the END STATE (installed hook is executable),
# not that install.sh explicitly calls chmod. Removing install.sh's do_chmod_x
# call is invisible here because `cp` already carries mode 755 from the source
# files tracked in git; the check only catches a hook that is non-executable
# for a real reason (e.g. source file lost its +x bit in git).
# ---------------------------------------------------------------------------
hk_count=0; hk_fail=0
for f in "$REPO_ROOT/.agents/hooks/"*.sh; do
  case "$(basename "$f")" in ledger-*) continue ;; esac
  hk_count=$((hk_count + 1))
  dest="$CLAUDE_HOME/.claude/hooks/$(basename "$f")"
  if [ ! -f "$dest" ]; then
    echo "  missing: $dest"; hk_fail=$((hk_fail + 1))
  elif [ ! -x "$dest" ]; then
    echo "  not executable: $dest"; hk_fail=$((hk_fail + 1))
  fi
done
if   [ "$hk_count" -eq 0 ]; then _fail "hooks-executable" "enumeration found nothing — check proves nothing"
elif [ "$hk_fail"  -eq 0 ]; then _pass "hooks-executable ($hk_count checked)"
else _fail "hooks-executable" "$hk_fail issue(s) across $hk_count hooks"; fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "$pass/$((pass + fail)) install-coverage tests passed"
[ "$fail" -eq 0 ]
