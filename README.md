# claude-code-model-routing

A global `CLAUDE.md` configuration that routes tasks to the right Claude model automatically — Opus for reasoning, Sonnet for implementation, Haiku for I/O.

## Why

Claude Code defaults to one model for everything. That means you're either paying Opus prices for reading files, or using Haiku for architecture decisions. Neither is optimal.

This configuration turns Claude Code into a self-routing system:

- **Opus** acts as a senior engineer — planning, debugging, reviewing
- **Sonnet** handles implementation — writing code, fixing tests, refactoring
- **Haiku** does the grunt work — reading files, generating boilerplate, searching

Each subagent runs in its own context window, so heavy I/O work never pollutes your main session. This stretches your weekly usage limit significantly.

## Setup

### 1. Global CLAUDE.md

Copy `CLAUDE.md` to your Claude global config directory:

```bash
cp CLAUDE.md ~/.claude/CLAUDE.md
```

This applies the routing rules to every project automatically.

### 2. Subagent files

Copy the agent definitions to your Claude agents directory:

```bash
cp -r .claude/agents ~/.claude/agents
```

Or per-project by placing them in `.claude/agents/` in your repo root.

### 3. Start Claude Code on Opus

```bash
claude --model claude-opus-4-7
```

The routing rules in `CLAUDE.md` will instruct Opus to delegate automatically.

## How it works

```
Your prompt
    │
    ▼
Opus (main session)
    │
    ├── I/O task? ──────────► Haiku subagent
    │                          - File reading
    │                          - Boilerplate generation
    │                          - Codebase search
    │                          - Documentation
    │
    ├── Code task? ─────────► Sonnet subagent
    │                          - Implementation
    │                          - Test writing
    │                          - Refactoring
    │                          - Code review
    │
    └── Reasoning task? ────► Opus (stays local)
                               - Architecture decisions
                               - Debugging subtle bugs
                               - Security review
                               - Planning
```

## Key rules

**File reading** — Opus never reads large files directly. It delegates to Haiku, and only passes the relevant subset — specific functions, line ranges, or interface definitions — never full files when a subset is sufficient.

**Boilerplate** — Tests, config files, fixtures, and repetitive patterns go to Haiku. Opus reviews the output.

**Documentation** — Never written directly. Haiku handles it with conversation context, Opus approves.

**Code review** — After every Sonnet implementation, Opus reviews before the task is considered done.

## Included agents

| Agent | Model | Purpose |
|---|---|---|
| `reader` | Haiku | File reading, codebase search, summarization |
| `implementer` | Sonnet | Writing code, fixing tests, refactoring |

## Bonus: .claudeignore

A universal `.claudeignore` is included. Copy it into any project to prevent Claude from reading files that waste tokens or should never be read — dependencies, build output, lock files, logs, secrets, and binaries.

```bash
cp .claudeignore /your/project/.claudeignore
```

Highlights:
- `node_modules/` and `vendor/` — prevents accidental dependency reads
- `package-lock.json`, `yarn.lock`, `composer.lock`, `go.sum` — lock files are huge and useless for Claude
- `.env` and `*.key` — keeps secrets out of Claude's context
- `storage/logs/` and `*.log` — log files are rarely what you want Claude reading

## Compatibility

Works with any tech stack. The routing is based on task type, not language or framework. Tested with Laravel and Go projects but applies universally.

## License

MIT
