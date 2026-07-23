#!/usr/bin/env bash
# tests/test-codex-skills.sh — verify Codex skill install from workflows
#
# Asserts that install.sh --codex --apply correctly transforms every workflow
# into a ~/.agents/skills/<name>/ directory containing a valid SKILL.md, that
# real skills are still installed, and that no stray bare .md files exist.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"

pass=0
fail=0

_pass() { echo "PASS $1"; pass=$((pass + 1)); }
_fail() { echo "FAIL $1 — $2"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Setup — run install into a temp HOME
# ---------------------------------------------------------------------------
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT

HOME="$FAKE_HOME" bash "$INSTALL" --codex --apply >/dev/null 2>&1

SKILLS_DIR="$FAKE_HOME/.agents/skills"

# ---------------------------------------------------------------------------
# Collision map: workflow basenames that collide with real skill directories
# get renamed to <name>-workflow. Compute the same way install.sh does.
# ---------------------------------------------------------------------------
collision_names=""
for skill_dir in "$REPO_ROOT/.agents/skills/"/*/; do
  collision_names="${collision_names} $(basename "${skill_dir%/}")"
done

workflow_skill_name() {
  local base="$1"
  for cname in $collision_names; do
    if [ "$cname" = "$base" ]; then
      echo "${base}-workflow"
      return
    fi
  done
  echo "$base"
}

# ---------------------------------------------------------------------------
# Collect expected names
# ---------------------------------------------------------------------------
expected_workflow_skill_names=()
for f in "$REPO_ROOT/.agents/workflows/"*.md; do
  base="$(basename "$f" .md)"
  expected_workflow_skill_names+=("$(workflow_skill_name "$base")")
done

# Count real skills
real_skill_count=0
for skill_dir in "$REPO_ROOT/.agents/skills/"/*/; do
  real_skill_count=$((real_skill_count + 1))
done

workflow_count="${#expected_workflow_skill_names[@]}"

# ---------------------------------------------------------------------------
# Assertion 1 — every workflow produced a directory with SKILL.md
# ---------------------------------------------------------------------------
a1_fail=0
for skill_name in "${expected_workflow_skill_names[@]}"; do
  skill_md="$SKILLS_DIR/$skill_name/SKILL.md"
  if [ ! -d "$SKILLS_DIR/$skill_name" ]; then
    echo "  missing directory: $SKILLS_DIR/$skill_name"
    a1_fail=$((a1_fail + 1))
  elif [ ! -f "$skill_md" ]; then
    echo "  missing SKILL.md in: $SKILLS_DIR/$skill_name"
    a1_fail=$((a1_fail + 1))
  fi
done
if [ "$a1_fail" -eq 0 ]; then
  _pass "A1: all ${workflow_count} workflows produced a directory with SKILL.md"
else
  _fail "A1: workflow directories" "${a1_fail} workflow(s) missing directory or SKILL.md"
fi

# ---------------------------------------------------------------------------
# Assertion 2 — each SKILL.md has valid frontmatter with non-empty name and description
# ---------------------------------------------------------------------------
a2_fail=0
for skill_name in "${expected_workflow_skill_names[@]}"; do
  skill_md="$SKILLS_DIR/$skill_name/SKILL.md"
  [ -f "$skill_md" ] || continue

  # Check that file starts with ---
  first_line=$(head -1 "$skill_md")
  if [ "$first_line" != "---" ]; then
    echo "  no opening --- in: $skill_md"
    a2_fail=$((a2_fail + 1))
    continue
  fi

  # Extract name and description values from frontmatter
  fm_name=$(awk '/^---/{if(++c==1){next}else{exit}} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$skill_md")
  fm_desc=$(awk '/^---/{if(++c==1){next}else{exit}} c==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$skill_md")

  if [ -z "$fm_name" ]; then
    echo "  empty 'name' in frontmatter: $skill_md"
    a2_fail=$((a2_fail + 1))
  fi
  if [ -z "$fm_desc" ]; then
    echo "  empty 'description' in frontmatter: $skill_md"
    a2_fail=$((a2_fail + 1))
  fi
done
if [ "$a2_fail" -eq 0 ]; then
  _pass "A2: all workflow SKILL.mds have non-empty name and description in frontmatter"
else
  _fail "A2: frontmatter validity" "${a2_fail} field(s) missing or empty"
fi

# ---------------------------------------------------------------------------
# Assertion 3 — name in frontmatter matches directory name
# ---------------------------------------------------------------------------
a3_fail=0
for skill_name in "${expected_workflow_skill_names[@]}"; do
  skill_md="$SKILLS_DIR/$skill_name/SKILL.md"
  [ -f "$skill_md" ] || continue

  fm_name=$(awk '/^---/{if(++c==1){next}else{exit}} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$skill_md")
  if [ "$fm_name" != "$skill_name" ]; then
    echo "  name mismatch in $skill_name/SKILL.md: got '$fm_name', expected '$skill_name'"
    a3_fail=$((a3_fail + 1))
  fi
done
if [ "$a3_fail" -eq 0 ]; then
  _pass "A3: name in frontmatter matches directory name for all workflow skills"
else
  _fail "A3: name/directory match" "${a3_fail} mismatch(es)"
fi

# ---------------------------------------------------------------------------
# Assertion 4 — real skills are still installed as directories with SKILL.md
# ---------------------------------------------------------------------------
a4_fail=0
for skill_dir in "$REPO_ROOT/.agents/skills/"/*/; do
  skill_name="$(basename "${skill_dir%/}")"
  installed="$SKILLS_DIR/$skill_name"
  if [ ! -d "$installed" ]; then
    echo "  missing real skill directory: $installed"
    a4_fail=$((a4_fail + 1))
  elif [ ! -f "$installed/SKILL.md" ]; then
    echo "  missing SKILL.md for real skill: $installed"
    a4_fail=$((a4_fail + 1))
  fi
done
if [ "$a4_fail" -eq 0 ]; then
  _pass "A4: all ${real_skill_count} real skills installed as directories with SKILL.md"
else
  _fail "A4: real skills" "${a4_fail} skill(s) missing directory or SKILL.md"
fi

# ---------------------------------------------------------------------------
# Assertion 5 — no stray bare .md files directly in ~/.agents/skills/
# ---------------------------------------------------------------------------
stray_count=0
stray_list=""
while IFS= read -r f; do
  stray_count=$((stray_count + 1))
  stray_list="${stray_list} $(basename "$f")"
done < <(find "$SKILLS_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null)

if [ "$stray_count" -eq 0 ]; then
  _pass "A5: no stray bare .md files directly in ~/.agents/skills/"
else
  _fail "A5: stray .md files" "${stray_count} stray file(s):${stray_list}"
fi

# ---------------------------------------------------------------------------
# Assertion 6 — no silent collision overwrote anything: total directory count
#               equals real_skill_count + workflow_count
# ---------------------------------------------------------------------------
expected_total=$((real_skill_count + workflow_count))
actual_total=0
while IFS= read -r _d; do
  actual_total=$((actual_total + 1))
done < <(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

if [ "$actual_total" -eq "$expected_total" ]; then
  _pass "A6: total directory count is ${actual_total} (${real_skill_count} skills + ${workflow_count} workflows, no collisions)"
else
  _fail "A6: collision check" "expected ${expected_total} directories (${real_skill_count}+${workflow_count}), got ${actual_total}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "${pass}/$((pass + fail)) assertion groups passed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
