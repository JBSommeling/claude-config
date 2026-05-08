#!/bin/bash
# PreToolUse hook: block Opus from writing/editing config/boilerplate files.
# Exits 2 to deny the tool call; stderr is shown to the model.
set -u
input=$(cat)
file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if [[ -z "$file_path" ]]; then
  exit 0
fi

if [[ "$file_path" =~ (Makefile|.*\.toml|.*\.ya?ml|.*config\.(js|ts|cjs|mjs)|tsconfig.*\.json|\.gitignore|\.air\.toml|Cargo\.toml|package\.json)$ ]]; then
  echo "Config/boilerplate file — delegate to Haiku subagent per CLAUDE.md" >&2
  exit 2
fi
exit 0
