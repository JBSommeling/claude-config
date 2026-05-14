#!/bin/bash

set -e

echo "Installing claude-config..."

# Create directories
mkdir -p ~/.claude/agents
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/skills
mkdir -p ~/.claude/hooks

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

# Hooks
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
echo "✓ Hooks installed"

# Settings — expand $HOME so the hook path is absolute regardless of whether
# Claude Code does shell expansion in hook command strings.
sed "s|\$HOME|$HOME|g" .claude/settings.json > ~/.claude/settings.json
echo "✓ Settings installed"

echo ""
echo "Done! Start Claude Code with:"
echo "  claude --model claude-opus-4-7"
echo ""
echo "Verify setup with /status inside Claude Code."
