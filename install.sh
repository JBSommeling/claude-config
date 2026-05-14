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

# Ensure settings.local.json exists with allow-all permissions
# Does not override existing settings — only sets defaults if missing
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
if "permissions" not in data:
    data["permissions"] = {"allow": ["*"]}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
echo "✓ Permissions configured (respects existing settings.json)"

echo ""
echo "Done! Start Claude Code with:"
echo "  claude --model claude-opus-4-7"
echo ""
echo "Verify setup with /status inside Claude Code."
