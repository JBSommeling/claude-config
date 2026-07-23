# Adapter-based hook portability

**Status:** Accepted
**Date:** 2026-07-22

Two `PreToolUse` guard scripts (delegation enforcement, push protection) needed to work on both Claude Code and Codex. Research established that the stdin field names, deny envelope shape, and exit-code contract are identical across platforms. The genuine difference is that Codex routes file edits through `apply_patch` (with raw patch text in `tool_input.command`, no `tool_input.file_path`), while `Edit`, `Write`, `MultiEdit`, and `NotebookEdit` have no Codex payload equivalent. We isolate all platform I/O behind `lib/adapter-claude.sh` and `lib/adapter-codex.sh`, each exposing a common interface (`hook_tool_name`, `hook_cmd`, `hook_is_edit_tool`, `hook_edit_path`, `hook_is_subagent`, `hook_deny`, `hook_bypass`). Policy scripts contain zero `jq` paths and zero tool-name literals. `install.sh` copies exactly one adapter to the target as `lib/adapter.sh` — binding happens at install time with no runtime platform detection.

## Considered Options

**Separate implementations per platform** — one full copy of each policy script per platform. Rejected because it duplicates the detection logic, which is the valuable part.

**Single unmodified script with inline branches** — viable, since roughly two-thirds of each script is already platform-neutral. Rejected because inline branches would scatter unverified Codex assumptions across both policy scripts; the adapter quarantines them in one small file that can be corrected in isolation once tested against a real Codex install.

## Consequences

Adding a platform touches only `lib/`. Sourcing introduces a new failure mode: a missing adapter must deny explicitly rather than fail open, because on Codex a non-zero hook exit causes the tool call to proceed. Codex's hash-pinned hook trust covers the hook command string, not sourced files, so adapter edits do not re-trigger its review prompt.
