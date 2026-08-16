# claude-config

A shared configuration for **Claude Code** and **OpenAI Codex** — one source of truth, installed to both platforms, routing each task to the right model tier. Sharing config across both avoids vendor lock-in.

## Quick start

```bash
git clone https://github.com/JBSommeling/claude-config
cd claude-config
chmod +x install.sh && ./install.sh
```

`install.sh [--claude] [--codex] [--dry-run] [--apply]` — no platform flag installs both; `--dry-run` writes nothing; Codex needs `--apply` to write files.

Start Claude with `claude --model claude-opus-4-8`, then check `/status` for both CLAUDE.md files plus every agent, skill, and command. After a Codex `--apply`, run `/hooks` inside Codex to approve the hook scripts — trust is hash-pinned, so hooks silently no-op until approved and after any hook edit.

Routing is global, so a per-project file needs only codebase facts:

```markdown
## Project context
- Laravel 11, PHP 8.3
- Tests use Pest
- Main models in /app/Models
```

## How it works

Platform-neutral content lives in `.agents/`. `install.sh` assembles each agent from a per-platform header (`*.header.md` / `*.header.toml`) plus the shared body; anything in `.claude/workflows/` or `.codex/workflows/` overrides the shared copy for that platform.

The orchestrator stays in the main session and delegates every subtask to a cheaper tier:

| Tier | Claude | Codex | Handles |
|---|---|---|---|
| **Orchestrator** | Opus | gpt-5.6-sol | Planning, debugging, reviewing, deciding |
| **Implementer** | Sonnet (`claude-sonnet-4-6`) | gpt-5.6-terra | Writing code, fixing tests, refactoring |
| **Reader** | Haiku | gpt-5.6-luna | Reading files, searching, boilerplate |

Sonnet is pinned to `claude-sonnet-4-6`; the bare `sonnet` alias now resolves to Sonnet 5 with ~30% higher token cost. `Explore` is pinned to `haiku`.

```
.agents/           shared content: 7 agent bodies, 21 workflows, 14 skills, hooks, conventions.md
.claude/           Claude wiring: CLAUDE.md, settings.json, *.header.md
.codex/            Codex wiring: AGENTS.md, config.toml, *.header.toml
docs/adr/          7 architecture decision records
install.sh
```

Workflows install as `~/.claude/commands/<name>.md` (invoked `/name`) and `~/.agents/skills/<name>/SKILL.md` for Codex (invoked `$name`); invocation syntax is rewritten at install time. Design rationale lives in [`docs/adr/`](docs/adr).

## Agents

| Agent | Claude | Codex | Purpose |
|---|---|---|---|
| `reader` | Haiku | gpt-5.6-luna | File reading, search, summarization |
| `Explore` | Haiku | gpt-5.6-luna | Read-only broad search / fan-out |
| `implementer` | Sonnet (`claude-sonnet-4-6`) | gpt-5.6-terra | Writing code, fixing tests, refactoring |
| `test-engineer` | Sonnet (`claude-sonnet-4-6`) | gpt-5.6-terra | Test writing and coverage |
| `code-reviewer` | Opus | gpt-5.6-sol | Code review — used by `/review`, `/review-pr`, `/ship` |
| `security-auditor` | Opus | gpt-5.6-sol | Security review |
| `maintainer-reviewer` | Opus | gpt-5.6-sol | Five-year maintainability and house-style consistency — used by the pipelines and `/ship` |

## Codex specifics

- **Effort** is capped at medium across all Codex agents.
- **Enforcement** of delegation and commit ownership is *detective*, not preventive: `agent_id`/`agent_type` aren't reliably present in the shipped release ([ADR 0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md)). Both ship enabled, no-op until Codex populates those fields, then become preventive with no config change. Push protection is preventive.
- **Naming** — `diagnose`, `manual-test-plan`, `tdd`, and `zoom-out` collide with skill names in Codex's single namespace, so they install with a `-workflow` suffix.

## Guardrails

Three `PreToolUse` hooks enforce routing discipline, each session-bypassable:

- **Delegation** — blocks `Edit`/`Write`/`MultiEdit`/`NotebookEdit` and file-writing Bash (`>`/`>>`, `sed -i`, `perl -i`, `tee`, heredocs, `python -c`/`node -e`) from the orchestrator; edits go through `implementer`. Subagent calls, memory writes, and temp-path redirects are exempt. `CLAUDE_BYPASS_DELEGATION=1`.
- **Commit ownership** — only the orchestrator commits; `git commit` from a subagent is blocked. `CLAUDE_BYPASS_DELEGATION=1`.
- **Push protection** — blocks any `git push` resolving to the default branch (`gh repo view` → `origin/HEAD` → conventional names; fails closed if unresolved). `CLAUDE_BYPASS_PUSH_GUARD=1` / `CODEX_BYPASS_PUSH_GUARD=1`.

## Commands

`/name` in Claude Code, `$name` in Codex. Pipelines chain several skills and subagents; the rest load a single skill.

**Plan** — `/spec` write a spec before code · `/plan` break work into verifiable tasks with acceptance criteria · `/grill` stress-test a plan against your domain model, updating `CONTEXT.md` and ADRs inline

**Build** — `/build` implement the next task incrementally · `/tdd` · `/test` red-green-refactor, Prove-It pattern for bugs

**Debug** — `/diagnose` root cause without a fix · `/diagnose-fix` diagnose and fix, plus a regression test · `/diagnose-full-pipeline` · `/diagnose-full-pipeline-cycle` · `/diagnose-full-pipeline-cycle-beta` diagnose, then drive the fix to an open PR

**Review & test** — `/review` five-axis review (correctness, readability, architecture, security, performance) · `/review-cycle` loop until green, emitting residuals · `/review-pr` inline comments on a GitHub PR · `/test-adversarial` coverage gaps with proof, ranked by blast radius · `/manual-test-plan` per-step plan with literal expected outputs · `/ship` pre-launch checklist, go/no-go

**Refactor** — `/code-simplify` cut complexity without changing behavior · `/improve-architecture` deepening candidates as an HTML report, then grill the one you pick

**Pipelines** — `/full-pipeline` spec → plan → build → validate → PR, judged once by four parallel subagents · `/full-pipeline-cycle` adds an auto-fixing `/review-cycle` round (capped at 5) before the PR · `/full-pipeline-cycle-beta` adds adversarial test lenses to judging. Spec and plan are the only checkpoints. All pipeline commands accept an optional `repos=<path>`: sibling repositories under that path (direct children with a `.git` directory) become visible — the spec allocates work across them, the plan orders tasks contract-first, and build and PR phases run per repo. Absent the parameter, behaviour is unchanged.

**Meta** — `/plain` re-explain the last answer in plain English · `/zoom-out` step back for higher-level context

## Skills

Methodology playbooks the orchestrator reads before acting and delegates within. Most commands are thin entry points onto one of these.

| Skill | For |
|---|---|
| `spec-driven-development` | A spec before code, when requirements are vague |
| `planning-and-task-breakdown` | Splitting a spec into ordered, implementable tasks |
| `incremental-implementation` | Any change touching more than one file |
| `tdd` | Test-first feature and bug work |
| `diagnose` | Reproduce → minimise → hypothesise → instrument → fix → regression-test |
| `code-review` | Review inline or via a dispatched subagent |
| `code-simplification` | Working-but-messy code, behavior unchanged |
| `improve-codebase-architecture` | Consolidating coupled modules; more testable, AI-navigable code |
| `security-and-hardening` | Untrusted input, auth, sessions, storage, third-party integrations |
| `manual-test-plan` | Per-step manual plan with literal expected outputs |
| `grill-with-docs` | Challenging a plan against the domain model, updating `CONTEXT.md` and ADRs |
| `idea-refine` | Structured divergent/convergent thinking on an idea |
| `zoom-out` | Broader context on unfamiliar code |
| `write-a-skill` | Authoring new skills with progressive disclosure |

## .claudeignore

Copy the included `.claudeignore` into any project to stop the agent reading token-wasting files — `node_modules/`, `vendor/`, lock files, `.env` and `*.key`, logs, build output.

```bash
cp .claudeignore /your/project/.claudeignore
```

## License

MIT
