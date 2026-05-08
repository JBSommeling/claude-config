#!/bin/bash
# PreToolUse hook: block Opus from reading files >300 lines.
# Exits 2 to deny the tool call; stderr is shown to the model.
set -u
input=$(cat)
file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 0
fi

lines=$(wc -l < "$file_path" 2>/dev/null | tr -d ' ')
if [[ -n "$lines" && "$lines" -gt 300 ]]; then
  echo "File >300 lines ($lines) — delegate to Haiku subagent per CLAUDE.md" >&2
  exit 2
fi
exit 0
