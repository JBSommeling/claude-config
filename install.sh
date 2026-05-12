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
cp .claude/agents/reader.md ~/.claude/agents/reader.md
cp .claude/agents/implementer.md ~/.claude/agents/implementer.md
echo "✓ Agents installed"

# Commands
cp .claude/commands/tdd.md ~/.claude/commands/tdd.md
cp .claude/commands/diagnose.md ~/.claude/commands/diagnose.md
cp .claude/commands/zoom-out.md ~/.claude/commands/zoom-out.md
cp .claude/commands/request-code-review.md ~/.claude/commands/request-code-review.md
echo "✓ Commands installed"

# Skills
cp -r .claude/skills/write-a-skill ~/.claude/skills/write-a-skill
cp -r .claude/skills/diagnose ~/.claude/skills/diagnose
cp -r .claude/skills/tdd ~/.claude/skills/tdd
cp -r .claude/skills/zoom-out ~/.claude/skills/zoom-out
cp -r .claude/skills/request-code-review ~/.claude/skills/request-code-review
echo "✓ Skills installed"

# Hooks
cp hooks/block-config-writes.sh ~/.claude/hooks/block-config-writes.sh
cp hooks/block-large-reads.sh ~/.claude/hooks/block-large-reads.sh
chmod +x ~/.claude/hooks/block-config-writes.sh ~/.claude/hooks/block-large-reads.sh
echo "✓ Hooks installed"

# Merge PreToolUse hooks block into ~/.claude/settings.json
python3 <<'PY'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
home = os.path.expanduser("~")
data = {}
if os.path.exists(path):
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = {}
hooks = data.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
desired = [
    {
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": f"{home}/.claude/hooks/block-config-writes.sh"}],
    },
    {
        "matcher": "Read",
        "hooks": [{"type": "command", "command": f"{home}/.claude/hooks/block-large-reads.sh"}],
    },
]
for entry in desired:
    if entry not in pre:
        # Replace any existing entry with the same matcher, otherwise append.
        replaced = False
        for i, existing in enumerate(pre):
            if existing.get("matcher") == entry["matcher"]:
                pre[i] = entry
                replaced = True
                break
        if not replaced:
            pre.append(entry)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
echo "✓ settings.json hooks merged"

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
