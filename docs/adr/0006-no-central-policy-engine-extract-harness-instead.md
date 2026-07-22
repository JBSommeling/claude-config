# No central policy engine; extract the harness instead

**Status:** Accepted
**Date:** 2026-07-22

Three guard scripts (`enforce-delegation.sh`, `enforce-commit-ownership.sh`, `block-push.sh`) all enforce role-based policy, prompting a proposal for a shared `policy.sh` exposing `can_edit`, `can_commit`, `can_push`. Measured across the three scripts, authorization logic is roughly six lines total, while roughly 150 lines are detection ("does this shell command write a file?") and context gathering ("what is the default branch?"). A policy engine would centralize the six lines and leave the 150 where they are, so the abstraction would not sit where the complexity is. `can_edit` would also need tool name, file path, raw command, and subagent flag — a parameter list that reproduces the payload, which usually indicates a misplaced boundary. Instead, we extract `lib/common.sh` for the harness: reading stdin once, sourcing and existence-checking the adapter, checking the bypass env var, early-exiting on tool mismatch, and emitting the deny envelope. Decision logic stays inline in each hook. Separate files also match the hook-wiring model: each hook maps to its own matcher in `settings.json` / `config.toml`, and Codex pins hook trust per script.

## Consequences

Lower indirection now. Accepted risk that policy could scatter if rules grow unnoticed, mitigated by an explicit revisit trigger: extract `policy.sh` when a single decision must consult more than one signal (for example, edit permission depending on branch and role and path together), or when the rule count exceeds roughly six.
