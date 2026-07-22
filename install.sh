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

  # Commands — workflows live in .agents/workflows/ in the new layout
  cmd_count=0
  for f in "${SCRIPT_DIR}/.agents/workflows/"*.md; do
    do_cp "$f" "${HOME}/.claude/commands/"
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

  # Platform adapter — bind claude at install time so hooks use the right adapter
  do_cp "${SCRIPT_DIR}/.agents/hooks/lib/adapter-claude.sh" \
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

  # Skills — strip trailing slash (same BSD cp fix as Claude side)
  skill_count=0
  for dir in "${SCRIPT_DIR}/.agents/skills/"/*/; do
    do_cp_r "${dir%/}" "${HOME}/.agents/skills/"
    skill_count=$((skill_count + 1))
  done
  echo "  ${skill_count} skills -> ~/.agents/skills/"

  # Workflows → ~/.agents/skills/ as plain copies
  # TODO T9: transform each workflow into a SKILL.md wrapper instead of plain copy
  wf_count=0
  for f in "${SCRIPT_DIR}/.agents/workflows/"*.md; do
    do_cp "$f" "${HOME}/.agents/skills/"
    wf_count=$((wf_count + 1))
  done
  echo "  ${wf_count} workflows -> ~/.agents/skills/ (plain copy; T9 wrapper pending)"

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

  # Platform adapter — bind codex at install time
  do_cp "${SCRIPT_DIR}/.agents/hooks/lib/adapter-codex.sh" \
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
