# claude-config

One configuration for **Claude Code** and **OpenAI Codex**, built to spend fewer tokens. Opus plans, debugs, and reviews. It hands implementation to Sonnet, and reading, searching, and boilerplate to Haiku, so the expensive model only does the work that needs it. Hooks keep the split honest: the orchestrator can't edit files or commit itself, and pushes to the default branch are blocked.

On top of that sit skills and pipelines that take a change from spec to draft PR, with review built in. `install.sh` installs the same agents, skills, workflows, and hooks to both platforms (on Codex the tiers are gpt-5.6-sol, gpt-5.6-terra, and gpt-5.6-luna), so you aren't locked in to either vendor.

## Install

```bash
git clone https://github.com/JBSommeling/claude-config
cd claude-config
chmod +x install.sh && ./install.sh
```

With no platform flag, the installer targets both platforms.

| Flag | Effect |
|---|---|
| `--claude` | Install for Claude Code |
| `--codex` | Install for Codex |
| `--dry-run` | Write nothing |
| `--apply` | Required for Codex to write files |
| `--clean` | Back up installer-managed folders first (see below) |

### Starting clean

Without `--clean`, the installer lists leftover entries it did not write and leaves them alone. With `--clean`, it first moves the folders it manages into a timestamped backup, so you start from exactly what the repo ships:

| Moved | Backed up to |
|---|---|
| `~/.claude/{skills,agents,commands,hooks}` | `~/.claude/.backup-<ts>/` |
| `~/.agents/skills` | `~/.agents/.backup-<ts>/` |
| `~/.codex/{agents,hooks}` (only with `--apply`) | `~/.codex/.backup-<ts>/` |

Nothing else is touched: memory, projects, sessions, credentials, and `settings.local.json` stay where they are. Copy back anything you want to keep, then delete the backup.

```bash
./install.sh --clean --dry-run   # preview
./install.sh --clean
```

### Check the install

- **Claude Code:** start with `claude --model opus` and run `/status`. It should show both CLAUDE.md files and every agent, skill, and command.
- **Codex:** after an `--apply` install, run `/hooks` inside Codex and approve the hook scripts. Trust is pinned to each script's hash, so hooks silently do nothing until you approve them, and again after any hook edit.

### Per-project setup

Routing is global, so a project's own CLAUDE.md only needs facts about that codebase:

```markdown
## Project context
- Laravel 11, PHP 8.3
- Tests use Pest
- Main models in /app/Models
```

To stop the agent reading token-wasting files (`node_modules/`, `vendor/`, lock files, `.env` and `*.key`, logs, build output), copy the included `.claudeignore` into the project:

```bash
cp .claudeignore /your/project/.claudeignore
```

## How it works

### Model tiers

The orchestrator stays in the main session and delegates every subtask to a cheaper tier:

| Tier | Claude | Codex | Handles |
|---|---|---|---|
| **Orchestrator** | Opus | gpt-5.6-sol | Planning, debugging, reviewing, deciding |
| **Implementer** | Sonnet | gpt-5.6-terra | Writing code, fixing tests, refactoring |
| **Reader** | Haiku | gpt-5.6-luna | Reading files, searching, boilerplate |

On Claude, every agent uses the bare model alias (`haiku`, `sonnet`, `opus`), so each tier follows the current default model.

### Agents

| Agent | Claude | Codex | Purpose |
|---|---|---|---|
| `reader` | Haiku | gpt-5.6-luna | File reading, search, summarization |
| `Explore` | Haiku | gpt-5.6-luna | Read-only broad search / fan-out |
| `implementer` | Sonnet | gpt-5.6-terra | Writing code, fixing tests, refactoring |
| `test-engineer` | Sonnet | gpt-5.6-terra | Test writing and coverage |
| `code-reviewer` | Opus | gpt-5.6-sol | Code review — used by `/review`, `/review-pr`, `/ship` |
| `security-auditor` | Opus | gpt-5.6-sol | Security review |
| `maintainer-reviewer` | Opus | gpt-5.6-sol | Five-year maintainability and house-style consistency — used by the pipelines and `/ship` |

### Repository layout

```
.agents/           shared content: 7 agent bodies, 26 workflows, 20 skills, hooks, conventions.md
.claude/           Claude wiring: CLAUDE.md, settings.json, *.header.md
.codex/            Codex wiring: AGENTS.md, config.toml, *.header.toml
docs/adr/          7 architecture decision records
install.sh
```

Platform-neutral content lives in `.agents/`. `install.sh` builds each agent from a per-platform header (`*.header.md` or `*.header.toml`) plus the shared body. Anything in `.claude/workflows/` or `.codex/workflows/` overrides the shared copy on that platform.

Workflows install as `~/.claude/commands/<name>.md` for Claude (invoked as `/name`) and as `~/.agents/skills/<name>/SKILL.md` for Codex (invoked as `$name`); the installer rewrites invocation syntax to match. Design rationale lives in [`docs/adr/`](docs/adr).

## Guardrails

Three `PreToolUse` hooks back up the routing rules. Each can be bypassed for one session with an environment variable.

- **Delegation.** Blocks `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, and file-writing Bash (`>`/`>>`, `sed -i`, `perl -i`, `tee`, heredocs, `python -c`/`node -e`) from the orchestrator, so edits go through `implementer`. Subagent calls, memory writes, and redirects to temp paths are exempt. Bypass: `CLAUDE_BYPASS_DELEGATION=1`.
- **Commit ownership.** Only the orchestrator commits; `git commit` from a subagent is blocked. Bypass: `CLAUDE_BYPASS_DELEGATION=1`.
- **Push protection.** Blocks any `git push` that resolves to the default branch. The default branch is looked up via `gh repo view`, then `origin/HEAD`, then conventional names; if none resolves, the push is blocked. Bypass: `CLAUDE_BYPASS_PUSH_GUARD=1` or `CODEX_BYPASS_PUSH_GUARD=1`.

### On Codex

- **Effort** is capped at medium for every Codex agent.
- **Delegation and commit ownership** are enforced *detectively*, not preventively, because the shipped release doesn't reliably populate `agent_id`/`agent_type` ([ADR 0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md)). Both hooks ship enabled and no-op until Codex populates those fields; then they become preventive with no config change. Push protection is already preventive.
- **Naming.** `diagnose`, `manual-test-plan`, `tdd`, and `zoom-out` collide with skill names in Codex's single namespace, so they install with a `-workflow` suffix.

## Commands

Invoke as `/name` in Claude Code or `$name` in Codex. Pipelines chain several skills and subagents; every other command loads a single skill.

**Plan**
- `/spec` — write a spec before code
- `/plan` — break work into verifiable tasks with acceptance criteria
- `/grill` — stress-test a plan against your domain model, updating `CONTEXT.md` and ADRs inline

**Build**
- `/build` — implement the next task incrementally
- `/tdd`, `/test` — red-green-refactor; Prove-It pattern for bugs

**Debug**
- `/diagnose` — find the root cause without fixing it
- `/diagnose-fix` — diagnose and fix, plus a regression test
- `/diagnose-full-pipeline`, `/diagnose-full-pipeline-cycle` — diagnose, then drive the fix to an open PR through the matching pipeline

**Review and test**
- `/review` — five-axis review: correctness, readability, architecture, security, performance
- `/review-cycle` — loop `/review` and fixes until green, emitting residuals
- `/review-pr` — post inline comments on a GitHub PR
- `/test-adversarial` — find coverage gaps with proof, ranked by blast radius
- `/manual-test-plan` — per-step plan with literal expected outputs
- `/test-plan [branch | uncommitted | <base>..<head> | pr <n>] [--share]` — business-logic test plan as a pass/fail form, served locally or as a shareable claude.ai artifact with `--share`; triages failures, fixes confirmed bugs, and offers a re-test
- `/ship` — pre-launch checklist ending in go/no-go

**Refactor**
- `/code-simplify` — cut complexity without changing behavior
- `/improve-architecture` — report deepening candidates as HTML, then grill the one you pick

**Pipeline steps** (also usable alone)
- `/branch-preflight` — refuse to proceed on the default branch; fail closed when it can't tell
- `/validate` — run tests, build, linter, and type check, fixing until green

**Meta**
- `/plain` — re-explain the last answer in plain English
- `/zoom-out` — step back for higher-level context

### Pipelines

- `/full-pipeline` — spec → plan → build → validate → PR, judged once by four parallel subagents.
- `/full-pipeline-cycle` — the same, plus an auto-fixing `/review-cycle` round (capped at 3) before the PR.

The spec and plan are the only checkpoints; everything after runs on its own. Every pipeline runs `/branch-preflight` before the Phase 3 commits, `/code-simplify` at Phase 3b, and `/validate` after the build.

All pipeline commands accept an optional `repos=<path>`. Direct children of that path with a `.git` directory become visible as sibling repositories: the spec allocates work across them, the plan orders tasks contract-first, and the build, PR, review, and judging phases run per repo. Without the parameter, nothing changes.

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
| `interactive-test-plan` | Business-logic test plan as a pass/fail form, with failures triaged and confirmed bugs fixed from the results |
| `grill-with-docs` | Challenging a plan against the domain model, updating `CONTEXT.md` and ADRs |
| `idea-refine` | Structured divergent/convergent thinking on an idea |
| `zoom-out` | Broader context on unfamiliar code |
| `write-a-skill` | Authoring new skills with progressive disclosure |

### Third-party skills

| Skill | Source | For |
|---|---|---|
| `break-ui` | emilkowalski/skills | Stress a UI with worst-case data to find layout breakage |
| `review-animations` | emilkowalski/skills | Review motion code (web and React Native) against a high craft bar; React Native uses a local `STANDARDS-RN.md` |
| `animate-expo` | emilkowalski/skills | React Native and Expo animation decisions |
| `animate` | emilkowalski/skills | Build web animations, choosing the right curve, duration, and properties |
| `clarity` | addyosmani/clarity | Draft, rewrite, review, or lint reader-facing prose so it reads specific rather than generic |

## License

MIT
