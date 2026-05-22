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
        reader.md              # Haiku — file reading and codebase search
        implementer.md         # Sonnet — writing code and refactoring
        code-reviewer.md       # Persona — code review dispatch
        security-auditor.md    # Persona — security review dispatch
        test-engineer.md       # Persona — test writing dispatch
    commands/
        build.md
        code-simplify.md
        diagnose.md
        full-pipeline.md
        full-pipeline-cycle.md
        plan.md
        review.md
        review-cycle.md
        review-pr.md
        ship.md
        spec.md
        tdd.md
        test.md
        zoom-out.md
    skills/
        write-a-skill/
        diagnose/
        tdd/
        zoom-out/
        code-review/
        idea-refine/
        planning-and-task-breakdown/
        spec-driven-development/
        code-simplification/
        security-and-hardening/
        incremental-implementation/
hooks/
    enforce-delegation.sh             # PreToolUse hook — forces Edit/Write to go through a subagent
    block-push-to-default-branch.sh   # PreToolUse hook — blocks git push to the default branch
CLAUDE.md                  # Global routing rules and skill registry
.claudeignore              # Universal ignore file for any project
install.sh                 # One-command installer
```

## Setup

### 1. Clone and install globally

```bash
git clone https://github.com/JBSommeling/claude-config
cd claude-config
chmod +x install.sh && ./install.sh
```

This copies everything to your global Claude directory and applies routing rules, agents, skills, and commands to every project automatically.

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

Verify setup with `/status` inside Claude Code. You should see both CLAUDE.md files listed and all agents, skills, and commands available.

## How it works

```
Your prompt
    │
    ▼
Opus (main session)
    │
    ├── Relevant skill? ────► Read SKILL.md first
    │                          Check ~/.claude/skills/ for all available skills
    │
    ├── I/O task? ──────────► Haiku subagent (reader)
    │                          - File reading
    │                          - Boilerplate generation
    │                          - Codebase search
    │                          - Documentation
    │
    ├── Code task? ─────────► Sonnet subagent (implementer)
    │                          - Implementation
    │                          - Test writing
    │                          - Refactoring
    │
    ├── Review task? ───────► Persona subagent
    │                          - code-reviewer: catches issues before merge
    │                          - security-auditor: flags vulnerabilities
    │                          - test-engineer: writes and improves tests
    │
    └── Reasoning task? ────► Opus (stays local)
                               - Architecture decisions
                               - Debugging subtle bugs
                               - Security review
                               - Planning
```

## Development pipeline

`/full-pipeline` orchestrates the complete workflow:

```
/spec → /plan → /build (loop) → /validate → /review → /ship
```

Checkpoints after spec and plan for approval. Build, validate, review, and ship run automatically. Individual commands work standalone too.

## Key rules

**Delegation enforcement** — `Edit`, `Write`, `MultiEdit`, and `NotebookEdit` from the main Opus session are blocked by a `PreToolUse` hook (`hooks/enforce-delegation.sh`). Edits must go through the `implementer` subagent (Sonnet). Subagent calls pass through; memory writes under `~/.claude/projects/*/memory/` are exempt. Set `CLAUDE_BYPASS_DELEGATION=1` to disable the hook for a session when the overhead is clearly not worth it.

**Default-branch push protection** — A `PreToolUse` hook (`hooks/block-push-to-default-branch.sh`) blocks any `git push` whose target resolves to the repo default branch (e.g. `main`). Determines the default via `gh repo view`, then `origin/HEAD`, then conventional names; fails closed if it can't resolve. Set `CLAUDE_BYPASS_PUSH_GUARD=1` to disable for a session.

**File reading** — Opus never reads large files directly. It delegates to Haiku, and only passes the relevant subset — specific functions, line ranges, or interface definitions — never full files when a subset is sufficient.

**Boilerplate** — Tests, config files, fixtures, and repetitive patterns go to Haiku. Opus reviews the output.

**Documentation** — Never written directly. Haiku handles it with conversation context, Opus approves.

**Code review** — After every Sonnet implementation, Opus reviews before the task is considered done.

**Git safety** — All git write operations (commit, push, branch creation, merge, rebase, reset, tag, PR creation) require explicit user approval. Read-only git operations run freely.

## Included agents

| Agent | Model | Purpose |
|---|---|---|
| `reader` | Haiku | File reading, codebase search, summarization |
| `implementer` | Sonnet | Writing code, fixing tests, refactoring |
| `code-reviewer` | Opus | Code review dispatch — used by /review-pr, /ship, and /review |
| `security-auditor` | Opus | Security review dispatch |
| `test-engineer` | Sonnet | Test writing and coverage dispatch |

## Skills and commands

Skills and commands are auto-discovered from `~/.claude/skills/` and `~/.claude/commands/`. Check those directories for the full list of installed items.

Key workflows:

- **Spec-first development** — `/spec` → `/plan` → `/build` → `/validate` → `/review` → `/ship`, or run `/full-pipeline` to orchestrate the whole sequence
- **Spec-first with auto-fix** — `/full-pipeline-cycle` is the same pipeline but Phase 5 runs `/review-cycle` (auto-fix loop, capped at 5 iterations), then opens a PR with residual findings posted as inline comments, and Phase 6 judges via three parallel subagents (code-reviewer, security-auditor, test-engineer)
- **Test-driven development** — `/test` activates red-green-refactor for the session
- **Debugging** — `/diagnose` for disciplined debugging when the cause is unknown
- **Code quality** — `/review`, `/review-cycle` (auto-loops review + fix until five axes are green or a cap is reached; emits structured residuals, does not commit or push), `/review-pr` (posts inline comments on GitHub), `/code-simplify`, and the `code-review` skill
- **Security** — `/review` with the `security-and-hardening` skill and security-auditor agent

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
