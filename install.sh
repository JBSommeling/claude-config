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
cp .claude/agents/reader.md ~/.claude/agents/reader.md
cp .claude/agents/implementer.md ~/.claude/agents/implementer.md
echo "✓ Agents installed"

# Commands
cp .claude/commands/tdd.md ~/.claude/commands/tdd.md
cp .claude/commands/zoom-out.md ~/.claude/commands/zoom-out.md
echo "✓ Commands installed"

# Skills
cp -r .claude/skills/write-a-skill ~/.claude/skills/write-a-skill
cp -r .claude/skills/diagnose ~/.claude/skills/diagnose
cp -r .claude/skills/tdd ~/.claude/skills/tdd
cp -r .claude/skills/zoom-out ~/.claude/skills/zoom-out
echo "✓ Skills installed"

echo ""
echo "Done! Start Claude Code with:"
echo "  claude --model claude-opus-4-7"
echo ""
echo "Verify setup with /status inside Claude Code."
