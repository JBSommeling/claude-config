# Orchestrator holds exclusive commit rights

**Status:** Accepted
**Date:** 2026-07-22

Codex supports per-agent `sandbox_mode` (`read-only`, `workspace-write`, `danger-full-access`), which could enforce delegation structurally at the OS level — the orchestrator would be incapable of editing rather than merely forbidden. Claude Code cannot express this, because its permission denies are session-scoped and inherited by subagents. Rather than adopt asymmetric sandboxing, we establish the mirror constraint: only the orchestrator commits. `enforce-commit-ownership.sh` denies `git commit` from subagents, mirroring the delegation guard that denies edits from the root.

## Considered Options

**Read-only root sandbox on Codex** — a read-only root cannot write `.git`, so it cannot commit. Retaining orchestrator commits is a deliberate prior decision (commit `ed902f1` forbids commit-only subagents), so this option is closed.

**Dedicated committer subagent** — contradicts `ed902f1`, which rejects spending a full context load on a one-line command.

## Consequences

Root sandboxing on Codex is permanently unavailable under this constraint, and delegation enforcement stays detective. Both the delegation guard and the commit-ownership guard depend on the same primitive (`hook_is_subagent`), so both upgrade together if a worker-unique identifier appears. On Codex, commit ownership is detective for the same reason as delegation — see ADR 0003.
