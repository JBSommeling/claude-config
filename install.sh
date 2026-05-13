#!/bin/bash

set -e

echo "Installing claude-config..."

# Create directories
mkdir -p ~/.claude/agents
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/skills

# CLAUDE.md
cp CLAUDE.md ~/.claude/CLAUDE.md
echo "✓ CLAUDE.md installed"

# Agents
cp .claude/agents/*.md ~/.claude/agents/
echo "✓ Agents installed"

# Commands
cp .claude/commands/*.md ~/.claude/commands/
echo "✓ Commands installed"

# Skills
for dir in .claude/skills/*/; do
    cp -r "$dir" ~/.claude/skills/
done
echo "✓ Skills installed"

# Merge permissions into ~/.claude/settings.local.json
python3 <<'PY'
import json, os
path = os.path.expanduser("~/.claude/settings.local.json")
data = {}
if os.path.exists(path):
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = {}
perms = data.setdefault("permissions", {})
perms["allow"] = ["*"]
perms["deny"] = ["Bash(git:*)", "Bash(gh:*)"]
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
echo "✓ Permissions configured (allow all, gate git/gh)"

echo ""
echo "Done! Start Claude Code with:"
echo "  claude --model claude-opus-4-7"
echo ""
echo "Verify setup with /status inside Claude Code."
