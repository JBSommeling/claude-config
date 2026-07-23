# claude-config

A shared configuration for **Claude Code** and **OpenAI Codex** that installs to both platforms from a single source of truth, routing each task to the right model tier.

## Why

Sharing config across both platforms avoids vendor lock-in and keeps the option to switch later.

## Quick start

```bash
git clone https://github.com/JBSommeling/claude-config
cd claude-config
chmod +x install.sh && ./install.sh
```

```
install.sh [--claude] [--codex] [--dry-run] [--apply]
```

- No platform flag installs **both** Claude Code and Codex.
- `--dry-run` prints every action without writing anything.
- Codex requires `--apply` to write files; without it you get a dry run.

**Start Claude Code:**

```bash
claude --model claude-opus-4-8
```

Verify with `/status` — you should see both CLAUDE.md files plus every agent, skill, and command.

**Codex — trust the hooks.** After a Codex `--apply` install, run `/hooks` inside Codex to review and approve the installed hook scripts. Trust is hash-pinned: hooks silently do nothing until approved, and you must re-run `/hooks` after any hook edit.

**Per-project context (optional).** Routing is global, so each repo needs only a minimal file with codebase facts — no need to repeat routing rules:

```markdown
## Project context
- Laravel 11, PHP 8.3
- Tests use Pest
- Main models in /app/Models
```

## How it works

All platform-neutral content lives in `.agents/` (agent bodies, skills, workflows, hooks). At install time, `install.sh` assembles each agent by concatenating a per-platform header (`*.header.md` / `*.header.toml`) with the shared body. Platform-specific overrides in `.claude/workflows/` or `.codex/workflows/` replace the shared copy for that platform.

The orchestrator stays in the main session and delegates every subtask to a cheaper subagent:

| Tier | Claude | Handles |
|---|---|---|
| **Orchestrator** | Opus | Planning, debugging, reviewing, deciding |
| **Implementer** | Sonnet (`claude-sonnet-4-6`) | Writing code, fixing tests, refactoring |
| **Reader** | Haiku | Reading files, searching, boilerplate |

The Sonnet tier is pinned to `claude-sonnet-4-6` (not the bare `sonnet` alias, which now resolves to Sonnet 5 with ~30% higher token costs). `Explore` is likewise pinned to `haiku` via a local `.claude/agents/Explore.md`.

```
.agents/           shared, platform-neutral content (installs to both)
  agents/          6 shared agent instruction bodies
  workflows/       21 command / workflow definitions
  skills/          14 skill directories
  hooks/           guard + ledger scripts, lib/ (common.sh + adapters)
.claude/           Claude wiring: CLAUDE.md, settings.json, *.header.md
.codex/            Codex wiring: AGENTS.md, config.toml, *.header.toml
docs/adr/          6 architecture decision records
tests/             test suite
install.sh
```

Workflows install as `~/.claude/commands/<name>.md` for Claude Code (invoked as `/name`) and `~/.agents/skills/<name>/SKILL.md` for Codex (invoked as `$name`). Invocation syntax is rewritten at install time.

## Codex specifics

**Tier mapping.** The main session runs `gpt-5.6-sol` (orchestrator tier). Subagents:

| Agent | Model | Effort | Purpose |
|---|---|---|---|
| `reader` | gpt-5.6-luna ($1.00/$6.00/1M) | low | File reading, search, summarization |
| `explore` | gpt-5.6-luna ($1.00/$6.00/1M) | low | Broad codebase search / fan-out |
| `implementer` | gpt-5.6-terra ($2.50/$15.00/1M) | medium | Writing code, fixing tests, refactoring |
| `test-engineer` | gpt-5.6-terra ($2.50/$15.00/1M) | medium | Test writing and coverage |
| `code-reviewer` | gpt-5.6-sol ($5.00/$30.00/1M) | medium | Code review |
| `security-auditor` | gpt-5.6-sol ($5.00/$30.00/1M) | medium | Security review |

Reasoning effort is capped at medium across all Codex agents.

**Enforcement.** Push protection is preventive. Delegation and commit-ownership enforcement are *detective* rather than preventive because worker-identity fields (`agent_id`/`agent_type`) are not reliably present in the shipped release ([ADR 0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md)). They ship enabled and act as no-ops until Codex populates those fields, at which point enforcement becomes preventive automatically with no config change.

**Workflow naming.** Four workflows share a name with a skill (`diagnose`, `manual-test-plan`, `tdd`, `zoom-out`). Codex has one namespace, so these install with a `-workflow` suffix (e.g. `diagnose-workflow`).

## Guardrails

Three `PreToolUse` hooks enforce routing discipline. All are session-bypassable via environment variables.

- **Delegation enforcement** — `Edit`, `Write`, `MultiEdit`, and `NotebookEdit` from the main orchestrator session are blocked, as are Bash commands that write files (`>`/`>>` redirects, `sed -i`, `perl -i`, `tee`, heredocs, `python -c`/`node -e`). Edits must go through the `implementer` subagent. Subagent calls, memory writes, and temp-path redirects are exempt. Bypass: `CLAUDE_BYPASS_DELEGATION=1`.
- **Commit ownership** — only the orchestrator commits; `git commit` from a subagent is blocked. Bypass: `CLAUDE_BYPASS_DELEGATION=1` (Claude).
- **Default-branch push protection** — any `git push` whose target resolves to the repo default branch is blocked. Resolution order: `gh repo view` → `origin/HEAD` → conventional names; fails closed if unresolved. Bypass: `CLAUDE_BYPASS_PUSH_GUARD=1` (Claude) / `CODEX_BYPASS_PUSH_GUARD=1` (Codex).

## Commands

Invoked as `/name` in Claude Code or `$name` in Codex. Pipeline commands chain several skills and subagents; others load a single skill.

### Plan & specify

| Command | What it does |
|---|---|
| `/spec` | Write a structured specification before any code — the starting point for spec-driven development. |
| `/plan` | Break work into small, verifiable tasks with acceptance criteria and dependency ordering. |
| `/grill` | Stress-test a plan against your domain model; sharpens terminology and updates `CONTEXT.md` and ADRs inline as decisions settle. |

### Build

| Command | What it does |
|---|---|
| `/build` | Implement the next task incrementally — build, test, verify, commit. |
| `/tdd` · `/test` | Red-green-refactor loop: write a failing test, implement, verify. For bugs, uses the Prove-It pattern (a failing test that reproduces the bug first). |

### Debug

| Command | What it does |
|---|---|
| `/diagnose` | Reproduce → minimise → hypothesise → instrument — **without** applying a fix. |
| `/diagnose-fix` | Diagnose **and** fix — the full loop through the fix plus a regression test. |
| `/diagnose-full-pipeline-cycle` | Diagnose the root cause, then drive the fix through the full pipeline to an open PR. |
| `/diagnose-full-pipeline-cycle-beta` | Same, but with adversarial test lenses in judging (costs more agents). |

### Review & test

| Command | What it does |
|---|---|
| `/review` | Five-axis code review — correctness, readability, architecture, security, performance. |
| `/review-cycle` | Loop `/review` → fix findings until all five axes are green (or a cap is hit); emits structured residuals. |
| `/review-pr` | Review a GitHub PR and post inline comments with correct line references. |
| `/test-adversarial` | Run adversarial test lenses in parallel to find coverage gaps with proof, ranked by blast radius. |
| `/manual-test-plan` | Generate a manual test plan with literal expected outputs (JSON payloads, log lines, exit codes). |
| `/ship` | Run the pre-launch checklist via parallel fan-out to specialist personas; synthesize a go/no-go decision. |

### Refactor

| Command | What it does |
|---|---|
| `/code-simplify` | Reduce complexity for clarity — without changing behavior. |
| `/improve-architecture` | Surface deepening opportunities; present candidates as an HTML report with before/after diagrams, then grill the one you pick. |

### Full pipelines

| Command | What it does |
|---|---|
| `/full-pipeline-cycle` | spec → plan → build → validate. Phase 5 auto-fixes via `/review-cycle` (capped at 5 iterations), opens a PR with residuals as inline comments, Phase 6 judges via three parallel subagents. Spec and plan are the only checkpoints. |
| `/full-pipeline-cycle-beta` | Same pipeline with adversarial test lenses in the judging phase. |

### Meta

| Command | What it does |
|---|---|
| `/zoom-out` | Step back for broader, higher-level context. |

## Skills

Methodology playbooks the orchestrator reads before acting and delegates within. Many commands are thin entry points that load the matching skill.

| Skill | What it's for |
|---|---|
| `spec-driven-development` | Create a specification before coding. Use when starting new work with unclear or vague requirements. |
| `planning-and-task-breakdown` | Break a spec into ordered, implementable tasks. Use when work is too large to start or parallelizable. |
| `incremental-implementation` | Deliver changes incrementally. Use for any change touching more than one file. |
| `tdd` | Test-driven development with the red-green-refactor loop. Use for test-first feature and bug work. |
| `diagnose` | Disciplined diagnosis loop: reproduce → minimise → hypothesise → instrument → fix → regression-test. |
| `code-review` | Conduct code review inline or via a dispatched subagent. Use before merging or after a major feature. |
| `code-simplification` | Simplify working-but-messy code without changing behavior. |
| `improve-codebase-architecture` | Find deepening opportunities — consolidate coupled modules, make the codebase more testable and AI-navigable. |
| `security-and-hardening` | Harden code against vulnerabilities — untrusted input, auth, sessions, storage, third-party integrations. |
| `manual-test-plan` | Produce a per-step manual test plan with literal expected outputs. |
| `grill-with-docs` | Challenge a plan against the domain model; update `CONTEXT.md` and ADRs inline as decisions crystallise. |
| `idea-refine` | Refine an idea through structured divergent and convergent thinking. Trigger with "idea-refine" or "ideate". |
| `zoom-out` | Zoom out for broader context or a higher-level perspective on unfamiliar code. |
| `write-a-skill` | Author new skills with proper structure, progressive disclosure, and bundled resources. |

## Agents (Claude Code)

| Agent | Model | Purpose |
|---|---|---|
| `reader` | Haiku | File reading, codebase search, summarization |
| `Explore` | Haiku | Read-only broad search / fan-out (pinned) |
| `implementer` | Sonnet (`claude-sonnet-4-6`) | Writing code, fixing tests, refactoring |
| `test-engineer` | Sonnet (`claude-sonnet-4-6`) | Test writing and coverage |
| `code-reviewer` | Opus | Code review — used by `/review`, `/review-pr`, `/ship` |
| `security-auditor` | Opus | Security review |

## Architecture decisions

| ADR | Summary |
|---|---|
| [0001](docs/adr/0001-shared-agents-layout-for-multi-platform-config.md) | Top-level `.agents/` as the single source of truth; platform wiring in `.claude/` and `.codex/`. |
| [0002](docs/adr/0002-adapter-based-hook-portability.md) | Hook policy scripts carry zero platform I/O; differences isolated behind `lib/adapter-claude.sh` / `lib/adapter-codex.sh`. |
| [0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md) | Codex delegation enforcement is detective because `agent_id`/`agent_type` aren't reliably present in the shipped release. |
| [0004](docs/adr/0004-orchestrator-holds-exclusive-commit-rights.md) | Only the orchestrator commits; `enforce-commit-ownership.sh` mirrors the delegation guard in the other direction. |
| [0005](docs/adr/0005-workflows-install-as-codex-skills-not-prompts.md) | Workflows install as Codex skills, not prompts (which are deprecated and non-shareable). |
| [0006](docs/adr/0006-no-central-policy-engine-extract-harness-instead.md) | No shared `policy.sh`; per-hook authorization is ~6 lines and doesn't warrant extraction — `lib/common.sh` extracts harness boilerplate instead. |

## Tests

```bash
./tests/run.sh
```

157 checks covering hook fixtures (delegation, push guard, commit ownership), platform neutrality, agent assembly, the ledger, Codex skill install, and an install regression test against a pre-restructure baseline.

## .claudeignore

A universal `.claudeignore` is included. Copy it into any project to stop the agent from reading token-wasting files:

```bash
cp .claudeignore /your/project/.claudeignore
```

Highlights: `node_modules/`, `vendor/`, lock files, `.env` and `*.key`, `storage/logs/` and `*.log`, build output.

## License

MIT
