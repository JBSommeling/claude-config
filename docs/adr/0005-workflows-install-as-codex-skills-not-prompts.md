# Workflows install as Codex skills, not prompts

**Status:** Accepted
**Date:** 2026-07-22

The repo has 19 workflow definitions, installed on Claude Code as `~/.claude/commands/*.md` and invoked as `/name`. The literal Codex analogue is `~/.codex/prompts/*.md`, invoked as `/prompts:name`. Codex documentation states that custom prompts are deprecated in favour of skills, and prompts are local-only and cannot be shared via a repository. We install workflows as Codex skills in `.agents/skills/`, invoked as `$name`.

## Considered Options

**Port to `prompts/`** — a truer 1:1 mirror preserving slash-style invocation. Rejected because it targets a deprecated surface and loses repo shareability.

## Consequences

Invocation syntax differs between platforms (`/name` on Claude Code versus `$name` on Codex), so muscle memory does not transfer. Workflows gain repo shareability on Codex.
