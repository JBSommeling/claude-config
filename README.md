# claude-code-model-routing

A global `CLAUDE.md` configuration that routes tasks to the right Claude model automatically — Opus for reasoning, Sonnet for implementation, Haiku for I/O. Includes subagent definitions, skills, and custom slash commands.

## Why

Claude Code defaults to one model for everything. That means you're either paying Opus prices for reading files, or using Haiku for architecture decisions. Neither is optimal.

This configuration turns Claude Code into a self-routing system:

- **Opus** acts as a senior engineer — planning, debugging, reviewing
- **Sonnet** handles implementation — writing code, fixing tests, refactoring
- **Haiku** does the grunt work — reading files, generating boilerplate, searching

Each subagent runs in its own context window, so heavy I/O work never pollutes your main session. This stretches your weekly usage limit significantly.

## Repository structure

```
.claude/
    agents/
        reader.md          # Haiku — file reading and codebase search
        implementer.md     # Sonnet — writing code and refactoring
    commands/
        tdd.md             # /tdd — activates TDD mode for the session
        zoom-out.md        # /zoom-out — maps modules and callers before acting
    skills/
        write-a-skill/
            SKILL.md       # How to create new skills
        diagnose/
            SKILL.md       # Disciplined debugging loop
        tdd/
            SKILL.md       # Red-green-refactor workflow
        zoom-out/
            SKILL.md       # Code inspection on a higher level
CLAUDE.md                  # Global routing rules and skill registry
.claudeignore              # Universal ignore file for any project
```

## Setup

### 1. Install globally

Copy everything to your global Claude directory. This applies the routing rules, agents, skills, and commands to every project automatically.

```bash
mkdir -p ~/.claude/agents
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/skills

cp CLAUDE.md ~/.claude/CLAUDE.md

cp .claude/agents/reader.md ~/.claude/agents/reader.md
cp .claude/agents/implementer.md ~/.claude/agents/implementer.md

cp .claude/commands/tdd.md ~/.claude/commands/tdd.md
cp .claude/commands/zoom-out.md ~/.claude/commands/zoom-out.md

cp -r .claude/skills/write-a-skill ~/.claude/skills/write-a-skill
cp -r .claude/skills/diagnose ~/.claude/skills/diagnose
cp -r .claude/skills/tdd ~/.claude/skills/tdd
cp -r .claude/skills/zoom-out ~/.claude/skills/zoom-out
```

### 2. Add project-specific context (per repo) — optional

The global CLAUDE.md handles routing. Each project only needs a minimal file with codebase-specific context.

```bash
mkdir -p .claude
touch .claude/CLAUDE.md
```

Example project CLAUDE.md:

```markdown
## Project context
- Laravel 11, PHP 8.3
- Tests use Pest
- Main models in /app/Models
```

No need to repeat routing rules — they are inherited from the global file.

### 3. Copy .claudeignore per project

```bash
cp .claudeignore /your/project/.claudeignore
```

### 4. Start Claude Code on Opus

```bash
claude --model claude-opus-4-7
```

Verify the global and project files are both loaded:

```
/status
```

You should see both CLAUDE.md files listed and all agents, skills, and commands available.

## How it works

```
Your prompt
    │
    ▼
Opus (main session)
    │
    ├── Relevant skill? ────► Read SKILL.md first
    │                          - diagnose for bugs
    │                          - tdd via /tdd command
    │                          - zoom-out for unfamiliar code
    │                          - write-a-skill for new skills
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

## Included skills

Skills are loaded on demand — Opus reads only the relevant skill for the current task.

| Skill | Purpose |
|---|---|
| `write-a-skill` | Creating new agent skills with proper structure |
| `diagnose` | Disciplined debugging loop for hard bugs and performance regressions |
| `tdd` | Red-green-refactor workflow for test-driven development |
| `zoom-out` | Get a high-level map of unfamiliar code — modules, callers, and how it fits together |

## Included commands

| Command | Purpose |
|---|---|
| `/tdd` | Activates TDD mode — follows red-green-refactor for the session |
| `/zoom-out` | Maps modules, callers, and dependencies before acting in unfamiliar code |

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
