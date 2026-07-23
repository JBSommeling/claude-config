# claude-config

A shared configuration for **Claude Code** and **OpenAI Codex** that turns each CLI into a self-routing system: a top-tier model plans, reviews, and debugs, while cheaper tiers handle the reading, searching, and code-writing. One source of truth installs to both platforms.

## Why

Both Claude Code and Codex default to a single model for everything. You either overpay top-tier prices to read files, or you hand architecture decisions to a weak model. Neither is right.

This config splits every task across three tiers, each running in its own context window so heavy I/O never pollutes the main session:

| Tier | Claude | Codex | Handles |
|---|---|---|---|
| **Orchestrator** | Opus | gpt-5.6-sol | Planning, debugging, reviewing, deciding |
| **Implementer** | Sonnet | gpt-5.6-terra | Writing code, fixing tests, refactoring |
| **Reader** | Haiku | gpt-5.6-luna | Reading files, searching, boilerplate |

The orchestrator stays in the main session and delegates everything else to subagents.

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

**Codex only — trust the hooks.** After a Codex `--apply` install, run `/hooks` inside Codex to review and approve the installed hook scripts. Trust is hash-pinned: hooks silently do nothing until approved, and you must re-run `/hooks` after any hook edit.

**Per-project context (optional).** Routing is global, so each repo needs only a minimal file with codebase facts — no need to repeat routing rules:

```markdown
## Project context
- Laravel 11, PHP 8.3
- Tests use Pest
- Main models in /app/Models
```

## How routing works

```
Your prompt
    │
    ▼
Orchestrator (Opus / gpt-5.6-sol)
    │
    ├── Relevant skill? ────► Read SKILL.md first, then delegate within it
    │
    ├── I/O task? ──────────► Reader (Haiku / gpt-5.6-luna)
    │                          reading · search · boilerplate · docs
    │
    ├── Code task? ─────────► Implementer (Sonnet / gpt-5.6-terra)
    │                          implementation · tests · refactoring
    │
    ├── Review task? ───────► Specialist subagent
    │                          code-reviewer · security-auditor · test-engineer
    │
    └── Reasoning task? ────► Orchestrator stays local
                               architecture · subtle bugs · planning
```

## Commands

Commands are slash-command entry points you type as `/name` in Claude Code (or `$name` in Codex). Some are thin wrappers that load a single [skill](#skills); others compose several agents and skills into a multi-step pipeline.

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
| `/tdd` · `/test` | Run the red-green-refactor loop: write a failing test, implement, verify. For bugs, uses the Prove-It pattern (a failing test that reproduces the bug first). |

### Debug

| Command | What it does |
|---|---|
| `/diagnose` | Run the disciplined diagnosis loop (reproduce → minimise → hypothesise → instrument) **without** applying a fix. |
| `/diagnose-fix` | Diagnose **and** fix — the full loop through the fix plus a regression test. |
| `/diagnose-full-pipeline-cycle` | Diagnose the root cause, then drive the fix through the full converging pipeline to an open PR. |
| `/diagnose-full-pipeline-cycle-beta` | Same, but the pipeline uses adversarial test lenses in judging (costs more agents). |

### Review & test

| Command | What it does |
|---|---|
| `/review` | Five-axis code review — correctness, readability, architecture, security, performance. |
| `/review-cycle` | Loop `/review` → fix findings until all five axes are green (or a cap is hit); emits structured residuals. |
| `/review-pr` | Review a GitHub PR and post inline comments with correct line references. |
| `/test-adversarial` | Run adversarial test lenses in parallel to find coverage gaps with proof, then merge findings ranked by blast radius. |
| `/manual-test-plan` | Generate a manual test plan from the current branch's changes, with literal expected outputs (JSON payloads, log lines, exit codes). |
| `/ship` | Run the pre-launch checklist via parallel fan-out to specialist personas, then synthesize a go/no-go decision. |

### Refactor

| Command | What it does |
|---|---|
| `/code-simplify` | Reduce complexity for clarity and maintainability — without changing behavior. |
| `/improve-architecture` | Surface shallow modules and deepening opportunities, present candidates as an HTML report with before/after diagrams, then grill the one you pick. |

### Full pipelines

| Command | What it does |
|---|---|
| `/full-pipeline-cycle` | The full loop: spec → plan → build → validate. Phase 5 auto-fixes via `/review-cycle` (capped at 5 iterations), opens a PR with residuals as inline comments, and Phase 6 judges via three parallel subagents. Spec and plan are the only checkpoints — everything after runs automatically. |
| `/full-pipeline-cycle-beta` | Same pipeline, with adversarial test lenses in the judging phase (more agents, deeper coverage). |

### Meta

| Command | What it does |
|---|---|
| `/zoom-out` | Step back for broader, higher-level context — useful when you're unfamiliar with a section of code or how it fits the whole. |

## Skills

Skills are the methodology playbooks — the *how* behind the work. The orchestrator reads the relevant `SKILL.md` before acting, and delegates within it. Some auto-trigger from context (a skill fires when the situation matches its description); several are invoked directly by the command of the same name.

| Skill | What it's for |
|---|---|
| `spec-driven-development` | Create a specification before coding. Use when starting new work with unclear or vague requirements. |
| `planning-and-task-breakdown` | Break a spec into ordered, implementable tasks. Use when work is too large to start or parallelizable. |
| `incremental-implementation` | Deliver changes incrementally. Use for any change touching more than one file, or too big to land in one step. |
| `tdd` | Test-driven development with the red-green-refactor loop. Use for test-first feature and bug work. |
| `diagnose` | Disciplined diagnosis loop for hard bugs and performance regressions: reproduce → minimise → hypothesise → instrument → fix → regression-test. |
| `code-review` | Conduct code review, inline or via a dispatched subagent. Use before merging or after a major feature. |
| `code-simplification` | Simplify working-but-messy code for clarity, without changing behavior. |
| `improve-codebase-architecture` | Find deepening opportunities — consolidate coupled modules, make the codebase more testable and AI-navigable — informed by `CONTEXT.md` and ADRs. |
| `security-and-hardening` | Harden code against vulnerabilities. Use when handling untrusted input, auth, sessions, storage, or third-party integrations. |
| `manual-test-plan` | Produce a per-step manual test plan from branch changes, with literal expected outputs. |
| `grill-with-docs` | Challenge a plan against the domain model, sharpen terminology, and update `CONTEXT.md` and ADRs inline as decisions crystallise. |
| `idea-refine` | Refine an idea through structured divergent and convergent thinking. Trigger with "idea-refine" or "ideate". |
| `zoom-out` | Zoom out for broader context or a higher-level perspective on unfamiliar code. |
| `write-a-skill` | Author new skills with proper structure, progressive disclosure, and bundled resources. |

**Commands vs. skills.** A command is something you *invoke*; a skill is a playbook the agent *follows*. Many commands (`/spec`, `/plan`, `/tdd`, `/diagnose`, `/review`, `/code-simplify`, `/grill`, `/improve-architecture`, `/manual-test-plan`, `/zoom-out`) are thin entry points that load the matching skill. The pipeline commands (`/full-pipeline-cycle`, `/diagnose-fix`, and friends) chain several skills and subagents together.

## Agents

### Claude Code

| Agent | Model | Purpose |
|---|---|---|
| `reader` | Haiku | File reading, codebase search, summarization |
| `Explore` | Haiku | Read-only broad search / fan-out (pinned) |
| `implementer` | Sonnet (`claude-sonnet-4-6`) | Writing code, fixing tests, refactoring |
| `test-engineer` | Sonnet (`claude-sonnet-4-6`) | Test writing and coverage |
| `code-reviewer` | Opus | Code review — used by `/review`, `/review-pr`, `/ship` |
| `security-auditor` | Opus | Security review |

The Sonnet tier is pinned to `claude-sonnet-4-6` rather than the bare `sonnet` alias (which now resolves to Sonnet 5). Sonnet 5's new tokenizer (~30% more tokens for the same text) and adaptive-thinking-on-by-default raise token spend on implementation work. `Explore` is likewise pinned to `haiku` via a local `.claude/agents/Explore.md`, so search fan-out no longer runs on the uncontrolled harness-default tier.

### Codex

| Agent | Model | Effort | Purpose |
|---|---|---|---|
| `reader` | gpt-5.6-luna ($1.00/$6.00/1M) | low | File reading, search, summarization |
| `explore` | gpt-5.6-luna ($1.00/$6.00/1M) | low | Broad codebase search / fan-out |
| `implementer` | gpt-5.6-terra ($2.50/$15.00/1M) | medium | Writing code, fixing tests, refactoring |
| `test-engineer` | gpt-5.6-terra ($2.50/$15.00/1M) | medium | Test writing and coverage |
| `code-reviewer` | gpt-5.6-sol ($5.00/$30.00/1M) | medium | Code review |
| `security-auditor` | gpt-5.6-sol ($5.00/$30.00/1M) | medium | Security review |

Reasoning effort is capped at medium across all Codex agents.

## Guardrails

Three `PreToolUse` hooks enforce the routing discipline. All are session-bypassable via environment variables.

- **Delegation enforcement** — `Edit`, `Write`, `MultiEdit`, and `NotebookEdit` from the main orchestrator session are blocked, as are Bash commands that write files (`>`/`>>` redirects, `sed -i`, `perl -i`, `tee`, heredocs, `python -c`/`node -e`). Edits must go through the `implementer` subagent. Subagent calls, memory writes, and temp-path redirects are exempt. Bypass: `CLAUDE_BYPASS_DELEGATION=1`.
- **Commit ownership** — only the orchestrator commits; `git commit` from a subagent is blocked. Bypass: `CLAUDE_BYPASS_DELEGATION=1` (Claude).
- **Default-branch push protection** — any `git push` whose target resolves to the repo default branch is blocked. Resolution order: `gh repo view` → `origin/HEAD` → conventional names; fails closed if unresolved. Bypass: `CLAUDE_BYPASS_PUSH_GUARD=1` (Claude) / `CODEX_BYPASS_PUSH_GUARD=1` (Codex).

On Codex, delegation and commit-ownership enforcement are *detective* rather than preventive because worker-identity fields are not reliably present in the shipped release ([ADR 0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md)). They ship enabled and act as no-ops until Codex populates those fields — at which point enforcement becomes preventive automatically, with no config change.

## Repository layout

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

**How the shared layout works.** All platform-neutral content lives in `.agents/`. At install time, `install.sh` assembles each agent by concatenating a per-platform header (`*.header.md` / `*.header.toml`) with the shared body from `.agents/agents/`. Platform-specific overrides in `.claude/workflows/` or `.codex/workflows/` replace the shared copy for that platform.

Workflow destinations differ:

- **Claude Code** — each workflow becomes `~/.claude/commands/<name>.md`, invoked as `/name`.
- **Codex** — each becomes `~/.agents/skills/<name>/SKILL.md`, invoked as `$name`. Invocation syntax (`/name` → `$name`) is rewritten at install time so the repo stays platform-neutral.

**Collision note:** four workflows share a name with a skill (`diagnose`, `manual-test-plan`, `tdd`, `zoom-out`). Claude Code keeps commands and skills in separate namespaces, so there's no conflict. Codex has one namespace, so these four install with a `-workflow` suffix (e.g. `diagnose-workflow`).

## Platform capabilities

| Capability | Claude Code | Codex |
|---|---|---|
| Instructions file | CLAUDE.md | AGENTS.md |
| Shared skills | yes | yes |
| Shared workflows | `/name` | `$name` |
| Shared hook scripts | yes | yes, via adapter |
| Push guard | preventive | preventive |
| Delegation enforcement | preventive | detective |
| Commit ownership | preventive | detective |
| Agent routing | `.md` headers | `.toml` headers |
| Per-agent model pinning | yes | yes, plus reasoning effort |
| Per-agent sandboxing | no | yes, available |
| Per-tool permission allowlist | yes | no, policy tiers |
| MCP servers | yes | yes |
| Hook trust re-approval | not needed | required, hash-pinned |

Codex is stronger on per-agent sandboxing; Claude Code is stronger on per-tool permission allowlists.

## Tests

```bash
./tests/run.sh
```

78 tests covering hook fixtures (delegation, push guard, commit ownership), platform neutrality, agent assembly, the ledger, Codex skill install, and an install regression test against a pre-restructure baseline.

## Architecture decisions

| ADR | Summary |
|---|---|
| [0001](docs/adr/0001-shared-agents-layout-for-multi-platform-config.md) | Top-level `.agents/` as the single source of truth; platform wiring in `.claude/` and `.codex/`. |
| [0002](docs/adr/0002-adapter-based-hook-portability.md) | Hook policy scripts carry zero platform I/O; differences isolated behind `lib/adapter-claude.sh` / `lib/adapter-codex.sh`. |
| [0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md) | Codex delegation enforcement is detective because `agent_id`/`agent_type` aren't reliably present in the shipped release. |
| [0004](docs/adr/0004-orchestrator-holds-exclusive-commit-rights.md) | Only the orchestrator commits; `enforce-commit-ownership.sh` mirrors the delegation guard in the other direction. |
| [0005](docs/adr/0005-workflows-install-as-codex-skills-not-prompts.md) | Workflows install as Codex skills, not prompts (which are deprecated and non-shareable). |
| [0006](docs/adr/0006-no-central-policy-engine-extract-harness-instead.md) | No shared `policy.sh`; per-hook authorization is ~6 lines and doesn't warrant extraction — `lib/common.sh` extracts harness boilerplate instead. |

## .claudeignore

A universal `.claudeignore` is included. Copy it into any project to stop the agent from reading token-wasting files:

```bash
cp .claudeignore /your/project/.claudeignore
```

Highlights: `node_modules/`, `vendor/`, lock files, `.env` and `*.key`, `storage/logs/` and `*.log`, build output.

## License

MIT
