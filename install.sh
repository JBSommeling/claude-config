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

# Settings
cp .claude/settings.json ~/.claude/settings.json
echo "✓ Settings installed"

echo ""
echo "Done! Start Claude Code with:"
echo "  claude --model claude-opus-4-7"
echo ""
echo "Verify setup with /status inside Claude Code."
