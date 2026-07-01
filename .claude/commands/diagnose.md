Read ~/.claude/skills/diagnose/SKILL.md and follow it now in DIAGNOSE-ONLY mode. Build a feedback loop before touching any code.

Run Phases 1–4 and Phase 6. Skip Phase 5 (Fix + regression test) — do NOT apply a fix, do NOT write a regression test, and do NOT change code to fix the bug.

Phases 1–4: find and confirm the root cause, then report the diagnosis — the root cause, the evidence that proves it, and the hypothesis that held.

Phase 6 (Cleanup + post-mortem): remove every [DEBUG-...] probe, delete any throwaway harnesses, and deliver the post-mortem ("what would have prevented this bug?"). The fix-verification checklist items (original repro no longer reproduces, regression test passes) are N/A since no fix was applied — mark them as such.

If the user wants the bug fixed too, tell them to run /diagnose-fix.