# claude-config

A global configuration that routes tasks to the right AI model automatically, shared between Claude Code and OpenAI Codex. Opus (or the Codex orchestrator) handles reasoning; cheaper tiers handle implementation and I/O.

## Why

Both Claude Code and Codex default to one model for everything. That means you are either paying top-tier prices for reading files, or using a weak model for architecture decisions. Neither is optimal.

This configuration turns both platforms into self-routing systems:

- **Orchestrator** (Opus / gpt-5.6-sol) — planning, debugging, reviewing
- **Implementer** (Sonnet / gpt-5.6-terra) — writing code, fixing tests, refactoring
- **Reader** (Haiku / gpt-5.6-luna) — reading files, searching, boilerplate

Each subagent runs in its own context window, so heavy I/O work never pollutes the main session.

## Repository structure

```
.agents/           shared content, installs to both platforms
  agents/          6 shared agent instruction bodies
  workflows/       19 workflow definitions
  skills/          14 skill directories
  hooks/           guard scripts, ledger scripts, lib/ (common.sh + adapters)
.claude/           Claude wiring only: CLAUDE.md, settings.json,
                     agents/*.header.md, workflows/ overrides
.codex/            Codex wiring only: AGENTS.md, config.toml,
                     agents/*.header.toml, workflows/ overrides
docs/adr/          6 architecture decision records
tests/             test suite
install.sh
```

## Install

```bash
git clone https://github.com/JBSommeling/claude-config
cd claude-config
chmod +x install.sh && ./install.sh
```

```
install.sh [--claude] [--codex] [--dry-run] [--apply]
```

- No platform flag installs both Claude Code and Codex.
- `--dry-run` prints every action without writing anything.
- Codex requires `--apply` to write files; without it the installer shows a dry run.

### Post-install: trust hooks in Codex

> **Required.** After a Codex `--apply` install, run `/hooks` inside Codex to review and approve the installed hook scripts. Hook trust is hash-pinned — hooks silently do not run until they have been approved. Re-run `/hooks` after any hook edit.

### Starting Claude Code

```bash
claude --model claude-opus-4-8
```

Verify with `/status` inside Claude Code — you should see both CLAUDE.md files and all agents, skills, and commands listed.

### Add project-specific context (per repo, optional)

The global CLAUDE.md handles routing. Each project needs only a minimal file with codebase context:

```markdown
## Project context
- Laravel 11, PHP 8.3
- Tests use Pest
- Main models in /app/Models
```

No need to repeat routing rules — they are inherited from the global file.

## How the shared layout works

All platform-neutral content lives in `.agents/`. At install time, `install.sh` assembles each agent by concatenating a per-platform header (`*.header.md` / `*.header.toml`) with the shared body from `.agents/agents/`. Platform-specific overrides in `.claude/workflows/` or `.codex/workflows/` replace the shared copy for that platform.

**Workflow destinations differ by platform:**

- Claude Code: each workflow becomes `~/.claude/commands/<name>.md`, invoked as `/name`
- Codex: each workflow becomes `~/.agents/skills/<name>/SKILL.md`, invoked as `$name`

Invocation syntax in workflow content is rewritten at install time (`/name` → `$name`) so the repo stays platform-neutral.

**Collision note:** four workflows share a name with a skill (`diagnose`, `manual-test-plan`, `tdd`, `zoom-out`). Claude Code keeps commands and skills in separate namespaces, so there is no conflict. Codex has one namespace, so these four install with a `-workflow` suffix (e.g., `diagnose-workflow`).

## Platform capabilities

| Capability | Claude Code | Codex |
|---|---|---|
| Instructions file | CLAUDE.md | AGENTS.md |
| Shared skills | yes | yes |
| Shared workflows | `/name` | `$name` |
| Shared hook scripts | yes | yes, via adapter |
| Push guard | Preventive | Preventive |
| Delegation enforcement | Preventive | Detective |
| Commit ownership | Preventive | Detective |
| Agent routing | `.md` headers | `.toml` headers |
| Per-agent model pinning | yes | yes, plus reasoning effort |
| Per-agent sandboxing | no | yes, available |
| Per-tool permission allowlist | yes | no, policy tiers |
| MCP servers | yes | yes |
| Hook trust re-approval | not needed | required, hash-pinned |

Codex is stronger on per-agent sandboxing. Claude Code is stronger on per-tool permission allowlists.

> **Current:** Detective, due to current Codex payload limitations.
> **Upgrade path:** If Codex exposes a worker-unique identifier, `adapter-codex.sh` enables preventive enforcement with no change to shared policy or repository structure.
> **Not available:** Root sandboxing, by design — the orchestrator must retain commit access.

The delegation and commit-ownership guards ship **enabled** on Codex and act as no-ops while caller identity is unknown. If a Codex release starts populating the identity fields, enforcement becomes preventive automatically — no config change needed.

## How it works

```
Your prompt
    │
    ▼
Orchestrator (Opus / gpt-5.6-sol)
    │
    ├── Relevant skill? ────► Read SKILL.md first
    │
    ├── I/O task? ──────────► Reader subagent (Haiku / gpt-5.6-luna)
    │                          - File reading
    │                          - Codebase search
    │                          - Boilerplate, documentation
    │
    ├── Code task? ─────────► Implementer subagent (Sonnet / gpt-5.6-terra)
    │                          - Implementation
    │                          - Test writing
    │                          - Refactoring
    │
    ├── Review task? ───────► Specialist subagent
    │                          - code-reviewer: catches issues before merge
    │                          - security-auditor: flags vulnerabilities
    │                          - test-engineer: writes and improves tests
    │
    └── Reasoning task? ────► Orchestrator (stays local)
                               - Architecture decisions
                               - Debugging subtle bugs
                               - Planning
```

## Agents

### Claude Code

| Agent | Model | Purpose |
|---|---|---|
| `reader` | Haiku | File reading, codebase search, summarization |
| `Explore` | Haiku | Read-only broad codebase search / fan-out (pinned) |
| `implementer` | Sonnet (`claude-sonnet-4-6`) | Writing code, fixing tests, refactoring |
| `code-reviewer` | Opus | Code review — used by `/review`, `/review-pr`, `/ship` |
| `security-auditor` | Opus | Security review |
| `test-engineer` | Sonnet (`claude-sonnet-4-6`) | Test writing and coverage |

The Sonnet tier is pinned to `claude-sonnet-4-6` rather than the bare `sonnet` alias, which now resolves to Sonnet 5. Sonnet 5's new tokenizer (~30% more tokens for the same text) and adaptive-thinking-on-by-default raise token spend on implementation work. The built-in `Explore` agent is also pinned to `haiku` via a local `.claude/agents/Explore.md` definition; previously it inherited the uncontrolled harness-default search tier.

### Codex

| Agent | Model | Reasoning effort | Purpose |
|---|---|---|---|
| `reader` | gpt-5.6-luna ($1.00/$6.00/1M) | low | File reading, search, summarization |
| `explore` | gpt-5.6-luna ($1.00/$6.00/1M) | low | Broad codebase search / fan-out |
| `implementer` | gpt-5.6-terra ($2.50/$15.00/1M) | medium | Writing code, fixing tests, refactoring |
| `test-engineer` | gpt-5.6-terra ($2.50/$15.00/1M) | medium | Test writing and coverage |
| `code-reviewer` | gpt-5.6-sol ($5.00/$30.00/1M) | medium | Code review |
| `security-auditor` | gpt-5.6-sol ($5.00/$30.00/1M) | medium | Security review |

Reasoning effort is capped at medium across all agents.

## Development pipeline

`/full-pipeline` (Claude) / `$full-pipeline` (Codex) orchestrates the complete workflow:

```
spec → plan → build (loop) → validate → review → ship
```

Checkpoints after spec and plan for approval; the approved spec and plan are saved to `~/Desktop/<feature-slug>/`. Build, validate, review, and ship run automatically. Individual steps work standalone.

Key workflows:

- **Spec-first development** — `spec` → `plan` → `build` → `validate` → `review` → `ship`, or run `full-pipeline` to orchestrate the whole sequence
- **Spec-first with auto-fix** — `full-pipeline-cycle` runs the same pipeline but Phase 5 runs `review-cycle` (auto-fix loop, capped at 5 iterations), then opens a PR with residual findings as inline comments, and Phase 6 judges via three parallel subagents. Spec and plan checkpoints only; everything after runs automatically
- **Test-driven development** — `tdd` activates red-green-refactor for the session
- **Debugging** — `diagnose` runs the disciplined diagnosis loop without fixing; `diagnose-fix` diagnoses and applies the fix with a regression test; `diagnose-full-pipeline-cycle` diagnoses then drives the fix through the full pipeline to an open PR
- **Domain grilling** — `grill` stress-tests a plan against the project's domain model, sharpens terminology in CONTEXT.md, and creates ADRs as decisions crystallise
- **Architecture improvement** — `improve-architecture` surfaces shallow modules and deepening opportunities, presents candidates as an HTML report with before/after diagrams, and drops into a grilling loop on the candidate you pick
- **Code quality** — `review`, `review-cycle` (auto-loops review + fix until five axes are green or a cap is reached), `review-pr` (posts inline comments on GitHub), `code-simplify`

## Key rules

**Delegation enforcement** — `Edit`, `Write`, `MultiEdit`, and `NotebookEdit` from the main Opus session are blocked by a `PreToolUse` hook (`enforce-delegation.sh`). Bash commands that write files are also blocked — output redirections (`>`/`>>`), in-place editors (`sed -i`, `perl -i`), `tee`, heredocs into files, and inline interpreter writes (`python -c`, `node -e`). Edits must go through the `implementer` subagent. Subagent calls pass through; memory writes and redirections to temp paths are exempt. Set `CLAUDE_BYPASS_DELEGATION=1` to disable for a session.

On Codex, delegation enforcement is detective (see [ADR 0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md)).

**Commit ownership** — Only the orchestrator commits. `enforce-commit-ownership.sh` blocks `git commit` from subagents. On Codex this is detective for the same reason as delegation. Set `CLAUDE_BYPASS_DELEGATION=1` (Claude) to disable.

**Default-branch push protection** — `block-push.sh` blocks any `git push` whose target resolves to the repo default branch. Determines the default via `gh repo view`, then `origin/HEAD`, then conventional names; fails closed if it can't resolve. Set `CLAUDE_BYPASS_PUSH_GUARD=1` (Claude) or `CODEX_BYPASS_PUSH_GUARD=1` (Codex) to disable for a session.

**File reading** — The orchestrator never reads large files directly. It delegates to the reader agent and passes only the relevant subset — specific functions, line ranges, or interface definitions.

**Boilerplate** — Tests, config files, fixtures, and repetitive patterns go to the reader/implementer. The orchestrator reviews the output.

**Code review** — After every implementation, the orchestrator reviews before the task is considered done.

## Tests

```bash
./tests/run.sh
```

78 tests. Covers: hook fixtures (delegation, push guard, commit ownership), platform neutrality, agent assembly, ledger, Codex skill install, and an install regression test against a pre-restructure baseline.

## Architecture decisions

| ADR | Summary |
|---|---|
| [0001](docs/adr/0001-shared-agents-layout-for-multi-platform-config.md) | Top-level `.agents/` as single source of truth for shared content; platform-specific wiring in `.claude/` and `.codex/` |
| [0002](docs/adr/0002-adapter-based-hook-portability.md) | Hook policy scripts contain zero platform I/O; all platform differences isolated behind `lib/adapter-claude.sh` and `lib/adapter-codex.sh` |
| [0003](docs/adr/0003-detective-delegation-enforcement-on-codex.md) | Codex delegation enforcement is detective rather than preventive because `agent_id`/`agent_type` fields are not reliably present in the shipped release |
| [0004](docs/adr/0004-orchestrator-holds-exclusive-commit-rights.md) | Only the orchestrator commits; `enforce-commit-ownership.sh` mirrors the delegation guard in the other direction |
| [0005](docs/adr/0005-workflows-install-as-codex-skills-not-prompts.md) | Workflows install as Codex skills (`~/.agents/skills/`) rather than prompts, which are deprecated and non-shareable |
| [0006](docs/adr/0006-no-central-policy-engine-extract-harness-instead.md) | No shared `policy.sh`; authorization logic is ~6 lines per hook and does not warrant extraction; `lib/common.sh` extracts harness boilerplate instead |

## .claudeignore

A universal `.claudeignore` is included. Copy it into any project to prevent Claude from reading files that waste tokens:

```bash
cp .claudeignore /your/project/.claudeignore
```

Highlights: `node_modules/`, `vendor/`, lock files (`package-lock.json`, `composer.lock`, `go.sum`), `.env` and `*.key`, `storage/logs/` and `*.log`, build output.

## License

MIT
