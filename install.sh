#!/usr/bin/env bash
# install.sh — install claude-config for Claude Code and/or Codex
#
# Usage: install.sh [--claude] [--codex] [--dry-run] [--apply] [--help]
#
#   No platform flag  Install BOTH Claude Code and Codex configs
#   --claude          Install Claude Code config only
#   --codex           Install Codex config only
#   --dry-run         Print every action; write nothing
#   --apply           Actually write files (required for --codex; Claude writes by default)
#   --help            Print usage and exit 0
#
# Codex note: if --codex is selected without --apply, a dry-run is shown
# and nothing is written. Pass --apply to commit Codex files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
do_claude=false
do_codex=false
dry_run=false
apply=false

for arg in "$@"; do
  case "$arg" in
    --claude)  do_claude=true ;;
    --codex)   do_codex=true ;;
    --dry-run) dry_run=true ;;
    --apply)   apply=true ;;
    --help)
      cat <<'EOF'
Usage: install.sh [--claude] [--codex] [--dry-run] [--apply] [--help]

  No platform flag  Install BOTH Claude Code and Codex configs
  --claude          Install Claude Code config only
  --codex           Install Codex config only
  --dry-run         Print every action; write nothing
  --apply           Actually write files (required for --codex)
  --help            Print this help and exit 0

Claude note: Claude Code config is written by default (no --apply needed).
Codex note: if --codex is selected without --apply, only a dry-run is shown
            and nothing is written. Pass --apply to commit Codex files.

After a Codex --apply, run /hooks inside Codex to review and trust the
installed hooks. Trust is hash-pinned — re-run /hooks after any hook edit.
EOF
      exit 0
      ;;
    *)
      echo "Error: unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

# If neither platform flag is given, install both
if ! $do_claude && ! $do_codex; then
  do_claude=true
  do_codex=true
fi

# --------------------------------------------------------------------------
# Dry-run helpers
# --------------------------------------------------------------------------

# action — print an action line (prefixed with [dry-run] when dry_run=true)
action() {
  if $dry_run; then
    echo "[dry-run] $*"
  fi
  # In apply mode, actions run silently; progress shown via summary lines only
}

do_mkdir() {
  action "mkdir -p $1"
  $dry_run || mkdir -p "$1"
}

do_cp() {
  action "cp $1 -> $2"
  $dry_run || cp "$1" "$2"
}

# do_atomic_cp SRC DST — copy SRC to DST atomically (copy to a temp name in
# the destination directory, then mv) so an interrupted install cannot leave
# a half-written file (M1 fix for adapter copies).
do_atomic_cp() {
  action "cp (atomic) $1 -> $2"
  if ! $dry_run; then
    local _tmp="${2}.tmp$$"
    cp "$1" "$_tmp" && mv "$_tmp" "$2"
  fi
}

do_cp_r() {
  action "cp -r $1 -> $2"
  $dry_run || cp -r "$1" "$2"
}

do_rm_f() {
  action "rm -f $1"
  $dry_run || rm -f "$1"
}

do_chmod_x() {
  action "chmod +x $1"
  $dry_run || chmod +x "$1"
}

do_sed_expand_home() {
  local src="$1" dst="$2"
  action "sed \$HOME expansion: $src -> $dst"
  $dry_run || sed "s|\$HOME|${HOME}|g" "$src" > "$dst"
}

# --------------------------------------------------------------------------
# Codex invocation-syntax transform helpers
# --------------------------------------------------------------------------
# build_codex_transform_expr — emit a sed -E expression that rewrites
# /NAME → $NAME for every workflow name (longest names first so partial
# prefixes like /diagnose never shadow /diagnose-fix).
#
# Anchoring rules:
#   • preceded by ^  or  [^[:alnum:]/]   (not alphanumeric, not slash)
#   • followed by    [^[:alnum:]-]  or  $  (word boundary: not alphanum, not dash)
# This prevents matching URL path segments (https://host/ship) and
# slash-separated words (tasks/plan.md), while matching the typical
# markdown forms: `` `/ship` ``, "run /ship", "/ship is a..." etc.
#
# Delimiter is '#' (not '|') so the alternation '|' inside the expression
# is not confused with the sed s/// delimiter.
build_codex_transform_expr() {
  local names_alt
  names_alt=$(for f in "${SCRIPT_DIR}/.agents/workflows/"*.md; do
    name="$(basename "$f" .md)"
    printf '%d %s\n' "${#name}" "$name"
  done | sort -rn | awk '{print $2}' | tr '\n' '|' | sed 's/|$//')
  # In double-quoted string: $names_alt expands; \$ yields literal $ (shell strips \);
  # sed sees $ = end-of-line in pattern, literal $ in replacement.
  printf '%s' "s#(^|[^[:alnum:]/])/($names_alt)([^[:alnum:]-]|\$)#\1\$\2\3#g"
}

# codex_transform_file FILE EXPR — apply the Codex slash→dollar transform
# to FILE in place (no-op in dry_run mode).
#
# The expression is applied TWICE in a pipeline so that adjacent slash-commands
# separated by a single non-word character are both transformed. A single pass
# consumes the boundary character, leaving the second command untransformed:
#   "run /plan /build now" → after one pass: "run $plan /build now"
#   → after two passes:  "run $plan $build now"
codex_transform_file() {
  local file="$1" expr="$2"
  action "codex-transform /→\$ in: $file"
  if ! $dry_run; then
    sed -E "$expr" "$file" | sed -E "$expr" > "${file}.codextmp" && mv "${file}.codextmp" "$file"
  fi
}

# --------------------------------------------------------------------------
# Claude Code install
# --------------------------------------------------------------------------
install_claude() {
  echo ""
  echo "=== Claude Code ==="

  do_mkdir "${HOME}/.claude/agents"
  do_mkdir "${HOME}/.claude/commands"
  do_mkdir "${HOME}/.claude/skills"
  do_mkdir "${HOME}/.claude/hooks"
  do_mkdir "${HOME}/.claude/hooks/lib"

  # CLAUDE.md
  do_cp "${SCRIPT_DIR}/.claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"

  # Agents — assemble from header + shared body
  # Guard: abort if any shared body contains ''' (would break Codex TOML literal strings)
  for body in "${SCRIPT_DIR}/.agents/agents/"*.md; do
    if grep -q "'''" "$body" 2>/dev/null; then
      echo "ERROR: $body contains ''' which would terminate a TOML literal string early" >&2
      exit 1
    fi
  done

  agent_count=0
  for header in "${SCRIPT_DIR}/.claude/agents/"*.header.md; do
    name="${header##*/}"          # e.g., explore.header.md
    name="${name%.header.md}"     # e.g., explore
    body="${SCRIPT_DIR}/.agents/agents/${name}.md"

    # Derive output filename: explore -> Explore.md, others -> ${name}.md
    case "$name" in
      explore) out_name="Explore.md" ;;
      *)       out_name="${name}.md" ;;
    esac

    dest="${HOME}/.claude/agents/${out_name}"
    action "assemble claude agent: ${name} -> ${out_name}"
    $dry_run || cat "$header" "$body" > "$dest"
    agent_count=$((agent_count + 1))
  done
  echo "  ${agent_count} agents"

  # Commands — workflows live in .agents/workflows/ in the new layout.
  # A per-platform override in .claude/workflows/ replaces the shared copy.
  cmd_count=0
  for f in "${SCRIPT_DIR}/.agents/workflows/"*.md; do
    name="$(basename "$f")"
    override="${SCRIPT_DIR}/.claude/workflows/${name}"
    if [ -f "$override" ]; then
      do_cp "$override" "${HOME}/.claude/commands/"
    else
      do_cp "$f" "${HOME}/.claude/commands/"
    fi
    cmd_count=$((cmd_count + 1))
  done
  echo "  ${cmd_count} workflows -> ~/.claude/commands/"

  # Skills — strip trailing slash so BSD cp copies each skill as a DIRECTORY
  # (a trailing slash makes BSD cp dump the contents, producing a stray SKILL.md)
  do_rm_f "${HOME}/.claude/skills/SKILL.md"
  skill_count=0
  for dir in "${SCRIPT_DIR}/.agents/skills/"/*/; do
    do_cp_r "${dir%/}" "${HOME}/.claude/skills/"
    skill_count=$((skill_count + 1))
  done
  echo "  ${skill_count} skills"

  # Hooks
  hook_count=0
  for f in "${SCRIPT_DIR}/.agents/hooks/"*.sh; do
    do_cp "$f" "${HOME}/.claude/hooks/"
    do_chmod_x "${HOME}/.claude/hooks/$(basename "$f")"
    hook_count=$((hook_count + 1))
  done

  # Hooks lib/
  lib_count=0
  for f in "${SCRIPT_DIR}/.agents/hooks/lib/"*; do
    do_cp "$f" "${HOME}/.claude/hooks/lib/"
    lib_count=$((lib_count + 1))
  done

  # Platform adapter — bind claude at install time so hooks use the right adapter.
  # Copied atomically (temp + mv) so an interrupted install cannot leave a
  # half-written, truncated adapter that sources cleanly but fails at runtime.
  do_atomic_cp "${SCRIPT_DIR}/.agents/hooks/lib/adapter-claude.sh" \
               "${HOME}/.claude/hooks/lib/adapter.sh"

  echo "  ${hook_count} hooks, ${lib_count} lib files + adapter.sh"

  # Settings — expand $HOME so hook command paths are absolute
  do_sed_expand_home "${SCRIPT_DIR}/.claude/settings.json" \
                     "${HOME}/.claude/settings.json"
  echo "  settings.json (with \$HOME expanded)"

  echo ""
  if $dry_run; then
    echo "[dry-run] Claude install complete (nothing written)"
  else
    echo "Claude install complete."
    echo "Start Claude Code with: claude --model claude-opus-4-8"
    echo "Verify setup with /status inside Claude Code."
  fi
}

# --------------------------------------------------------------------------
# Codex install
# --------------------------------------------------------------------------
install_codex() {
  # Codex requires --apply to write; without it, force dry-run for this section.
  # Use a local shadow of $dry_run so the do_* helpers pick it up automatically
  # (bash dynamic scoping: local vars in a caller are visible in callees).
  local dry_run=$dry_run
  local codex_needs_apply=false
  if ! $apply; then
    dry_run=true
    codex_needs_apply=true
  fi

  echo ""
  echo "=== Codex ==="

  if $codex_needs_apply; then
    echo "[dry-run] --apply is required to write Codex files. Showing what would happen:"
  fi

  do_mkdir "${HOME}/.codex/agents"
  do_mkdir "${HOME}/.codex/hooks"
  do_mkdir "${HOME}/.codex/hooks/lib"
  do_mkdir "${HOME}/.agents/skills"

  # AGENTS.md
  do_cp "${SCRIPT_DIR}/.codex/AGENTS.md" "${HOME}/.codex/AGENTS.md"

  # config.toml — expand $HOME so hook command paths are absolute
  do_sed_expand_home "${SCRIPT_DIR}/.codex/config.toml" \
                     "${HOME}/.codex/config.toml"

  # Codex agents — assemble from header + shared body
  agent_count=0
  for header in "${SCRIPT_DIR}/.codex/agents/"*.header.toml; do
    name="${header##*/}"
    name="${name%.header.toml}"
    body="${SCRIPT_DIR}/.agents/agents/${name}.md"
    dest="${HOME}/.codex/agents/${name}.toml"

    action "assemble codex agent: ${name}.toml"
    if ! $dry_run; then
      { cat "$header"
        printf "developer_instructions = '''\n"
        cat "$body"
        printf "'''\n"
      } > "$dest"
    fi
    agent_count=$((agent_count + 1))
  done
  echo "  ${agent_count} agents"

  # Build the invocation-syntax transform expression once (used for skills + workflows).
  # Claude slash-commands (/name) are rewritten to Codex dollar-commands ($name)
  # at install time so shared content stays platform-neutral in the repo.
  codex_transform_expr="$(build_codex_transform_expr)"

  # Skills — strip trailing slash (same BSD cp fix as Claude side), then apply
  # the invocation-syntax transform to all markdown files in each skill.
  skill_count=0
  for dir in "${SCRIPT_DIR}/.agents/skills/"/*/; do
    skill_name="$(basename "${dir%/}")"
    do_cp_r "${dir%/}" "${HOME}/.agents/skills/"
    if ! $dry_run; then
      while IFS= read -r md_file; do
        codex_transform_file "$md_file" "$codex_transform_expr"
      done < <(find "${HOME}/.agents/skills/${skill_name}" -name "*.md" -type f)
    else
      action "codex-transform /→\$ in: ${HOME}/.agents/skills/${skill_name}/**/*.md"
    fi
    skill_count=$((skill_count + 1))
  done
  echo "  ${skill_count} skills -> ~/.agents/skills/"

  # Workflows → ~/.agents/skills/ as proper Codex skill directories.
  # Each workflow becomes ~/.agents/skills/<skill-name>/SKILL.md with valid frontmatter:
  #   name:        the skill directory name (workflow basename, or <basename>-workflow
  #                if the basename collides with a real skill directory)
  #   description: the workflow's own frontmatter description, or a synthesized one
  #                derived from the first non-empty body line when frontmatter is absent
  # The slash→dollar invocation-syntax transform is applied to the SKILL.md body.
  # A per-platform override in .codex/workflows/ replaces the shared workflow body.
  wf_count=0
  for f in "${SCRIPT_DIR}/.agents/workflows/"*.md; do
    wf_base="$(basename "$f" .md)"
    override="${SCRIPT_DIR}/.codex/workflows/${wf_base}.md"

    # Collision check: if a real skill directory shares this name, append -workflow
    skill_name="$wf_base"
    for _skill_dir in "${SCRIPT_DIR}/.agents/skills/"/*/; do
      if [ "$(basename "${_skill_dir%/}")" = "$wf_base" ]; then
        skill_name="${wf_base}-workflow"
        break
      fi
    done

    # Source file: per-platform override wins over the shared workflow
    src="$f"
    [ -f "$override" ] && src="$override"

    skill_dir_dest="${HOME}/.agents/skills/${skill_name}"
    skill_md="${skill_dir_dest}/SKILL.md"

    do_mkdir "$skill_dir_dest"
    action "write workflow skill: $skill_md"

    if ! $dry_run; then
      # Extract description and body.
      # Files with frontmatter (--- block): pull description from it and strip
      #   the block so the body is clean prose.
      # Files without frontmatter: synthesize description from first non-empty line.
      if head -1 "$src" | grep -q "^---"; then
        desc=$(awk '/^---/{if(++c==1){next}else{exit}} c==1 && /^description:/{
          sub(/^description:[[:space:]]*/,""); print; exit}' "$src")
        awk 'BEGIN{c=0; found=0} /^---/{if(++c==2){found=1; next}} found{print}' \
          "$src" > "${skill_md}.body"
      else
        desc=$(grep -m1 "." "$src" | cut -c1-120)
        cp "$src" "${skill_md}.body"
      fi

      # Write SKILL.md: frontmatter header + body
      {
        echo "---"
        echo "name: ${skill_name}"
        echo "description: ${desc}"
        echo "---"
        echo ""
        cat "${skill_md}.body"
      } > "$skill_md"
      rm -f "${skill_md}.body"

      # Apply the Codex slash→dollar invocation-syntax transform to the body
      codex_transform_file "$skill_md" "$codex_transform_expr"
    fi

    wf_count=$((wf_count + 1))
  done
  echo "  ${wf_count} workflows -> ~/.agents/skills/ (as skill directories)"

  # Hooks
  hook_count=0
  for f in "${SCRIPT_DIR}/.agents/hooks/"*.sh; do
    do_cp "$f" "${HOME}/.codex/hooks/"
    do_chmod_x "${HOME}/.codex/hooks/$(basename "$f")"
    hook_count=$((hook_count + 1))
  done

  # Hooks lib/
  lib_count=0
  for f in "${SCRIPT_DIR}/.agents/hooks/lib/"*; do
    do_cp "$f" "${HOME}/.codex/hooks/lib/"
    lib_count=$((lib_count + 1))
  done

  # Platform adapter — bind codex at install time (atomic copy).
  do_atomic_cp "${SCRIPT_DIR}/.agents/hooks/lib/adapter-codex.sh" \
               "${HOME}/.codex/hooks/lib/adapter.sh"

  echo "  ${hook_count} hooks, ${lib_count} lib files + adapter.sh"

  echo ""
  if $dry_run; then
    echo "[dry-run] Codex install complete (nothing written)"
    if $codex_needs_apply; then
      echo ""
      echo "Pass --apply to write these files."
    fi
  else
    echo "Codex install complete."
    echo ""
    echo "IMPORTANT: Run /hooks inside Codex to review and trust the installed hooks."
    echo "Trust is hash-pinned — re-run /hooks after any hook edit."
  fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
$do_claude && install_claude
$do_codex  && install_codex

echo ""
echo "Done."
