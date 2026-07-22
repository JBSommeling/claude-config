# Detective delegation enforcement on Codex

**Status:** Accepted
**Date:** 2026-07-22

On Claude Code the delegation guard distinguishes orchestrator from subagent via `agent_id` / `agent_type` in the `PreToolUse` payload. Codex's generated schema carries these as optional fields, but its documented release-behaviour page does not list them and explicitly warns that schema fields may not be present in a shipped release. This could not be verified — Codex is not installed on this machine. Shipping preventive enforcement against unverified fields risks blocking every subagent edit if the shipped release omits them. We therefore ship delegation enforcement on Codex as detective: delegation contracts stated in `AGENTS.md`, plus a ledger that appends records on `PreToolUse` for `apply_patch` and `spawn_agent` and reports at `Stop` any edits occurring outside a delegation window. The identity check exists in `adapter-codex.sh` but is disabled.

## Considered Options

**Capability files keyed on `session_id`** — authorize at spawn time, write a capability file, check for it in `PreToolUse`. Rejected on a documented Codex fact: subagent hooks report the *parent* session id. `session_id` is therefore shared between orchestrator and worker and cannot discriminate between them.

**Identity-only enforcement using undocumented fields** — would block every subagent edit if the shipped release omits the fields, making Codex unusable.

## Consequences

Codex delegation enforcement is weaker than Claude's — detective rather than preventive, due to current Codex payload limitations. Upgrade path: if Codex exposes a worker-unique identifier, `adapter-codex.sh` can enable preventive enforcement with no change to shared policy or repository structure. The ledger uses the same unreliable lifecycle events, but a missed SubagentStop leaves the depth counter elevated — edits inside the unclosed window are recorded as delegated when they were not (silent miss, not false positive). `ledger-report.sh` detects a non-zero depth at session end and emits a prominent warning to surface this condition.
