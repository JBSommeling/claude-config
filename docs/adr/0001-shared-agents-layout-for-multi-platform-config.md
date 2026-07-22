# Shared `.agents/` layout for multi-platform config

**Status:** Accepted
**Date:** 2026-07-22

The repo originally held only Claude Code config. Adding OpenAI Codex support required a layout that avoids duplicating the ~2,200 lines of platform-neutral content (skills and workflows). We adopted a top-level `.agents/` directory for shared content (skills, workflows, hooks), with `.claude/` and `.codex/` holding only platform-specific wiring. `install.sh` merges shared and platform content at install time by copying. `.agents/` was chosen because Codex already discovers skills at `.agents/skills/` — an existing convention rather than an invented one. Narrow `sed` substitution at install time handles mechanical differences (path and product-name rewrites) without a build system.

## Considered Options

**Duplicate parallel trees** — keep `.claude/` and add a full `.codex/` copy. Rejected because it duplicates ~2,200 lines that must never diverge.

**Source tree plus generator** — a neutral `source/` compiled by `build.sh` into `dist/claude/` and `dist/codex/`. Rejected as disproportionate: it adds a build step, generated artifacts, and templating syntax inside otherwise-clean markdown.

## Consequences

Single source of truth for shared content. One large rename commit in history. Files needing textual differences between platforms rely on install-time substitution rather than being editable per platform.
