# Hook Tests

Dependency-free test harness for the hook scripts. Captures current behaviour as golden tests.

## Running

```bash
# Run all fixtures and sub-suites
./tests/run.sh

# Run only fixtures whose name contains a substring
./tests/run.sh delegation
./tests/run.sh push
./tests/run.sh codex-commit
./tests/run.sh dot-claude
```

Exit code is 0 if all tests pass, 1 if any fail.

## How it works

Each fixture is a pair of files in `tests/fixtures/`:

| File | Contents |
|------|----------|
| `<name>.json` | The hook's stdin payload (the JSON the Claude hook system sends) |
| `<name>.expect` | Either `allow` or `deny` |

Optional sidecar files:

| File | Contents |
|------|----------|
| `<name>.codexenv` | Per-fixture env overrides, e.g. `CODEX_ENFORCE_DELEGATION=1` |
| `<name>.xfail` | Marks a known limitation; the test is expected to fail (XFAIL) |

The fixture filename prefix determines which hook is exercised and which adapter is used:

| Prefix | Hook | Adapter |
|--------|------|---------|
| `delegation-*` | `.agents/hooks/enforce-delegation.sh` | Claude Code (default) |
| `push-*` | `.agents/hooks/block-push.sh` | Claude Code (default) |
| `commit-*` | `.agents/hooks/enforce-commit-ownership.sh` | Claude Code (default) |
| `codex-delegation-*` | `.agents/hooks/enforce-delegation.sh` | Codex |
| `codex-push-*` | `.agents/hooks/block-push.sh` | Codex |
| `codex-commit-*` | `.agents/hooks/enforce-commit-ownership.sh` | Codex |

## Decision rule

The runner pipes the JSON into the hook and inspects the result:

- **deny** — stdout contains `"permissionDecision": "deny"` (with or without spaces around the colon), OR the hook exits with code 2.
- **allow** — anything else (hook exits 0 with no deny in stdout, or exits 0 with no output).

`CLAUDE_BYPASS_DELEGATION=0`, `CLAUDE_BYPASS_PUSH_GUARD=0`, and `CLAUDE_BYPASS_COMMIT_GUARD=0` are set explicitly when running hooks so the developer's own environment cannot skew results.

## Codex fixtures and `.codexenv`

Fixtures with the `codex-` prefix run against the Codex adapter (`adapter-codex.sh`). They simulate payloads as Codex sends them: file edits use `apply_patch` with the patch in `tool_input.command`; there is no `tool_input.file_path`.

A `.codexenv` sidecar file can set `CODEX_ENFORCE_DELEGATION=1` to enable strict mode for that fixture. Without it, the Codex adapter defaults to permissive mode (`CODEX_ENFORCE_DELEGATION=0`), which treats an unknown caller as allowed.

## The `.xfail` mechanism

Mark a fixture as a known limitation by creating `<name>.xfail` (contents ignored):
- **XFAIL** (actual ≠ expected, marker present): reported but not counted as a failure.
- **Unexpected PASS** (actual = expected, marker present): counted as a failure so the marker gets removed when the limitation is fixed.

## Sub-suites

In addition to the fixture loop, `run.sh` runs several standalone test scripts:

| Script | What it tests |
|--------|---------------|
| `tests/test-platform-neutrality.sh` | Agent bodies, workflows, and hook deny messages are platform-neutral |
| `tests/test-agent-assembly.sh` | Claude and Codex agent assembly produces expected output |
| `tests/test-ledger.sh` | Multi-step ledger stateful scenarios (spawn/edit/close/report) |
| `tests/test-codex-skills.sh` | Codex skills install produces correct directory layout |
| `tests/test-codex-adapter.sh` | Codex adapter path parsing (`hook_edit_path`, `hook_edit_paths`) |
| `tests/test-codex-transform.sh` | Slash-command→dollar-command transform in adjacent positions |
| `tests/test-push-guard.sh` | Push guard integration (forged origin/HEAD, metacharacter branch) |
| `tests/test-install.sh` | Install regression: file manifest and hook command paths |

## Adding a fixture

1. Create `tests/fixtures/<prefix>-<description>.json` with the hook payload.
2. Create `tests/fixtures/<prefix>-<description>.expect` containing either `allow` or `deny`.
3. Optionally create `tests/fixtures/<prefix>-<description>.codexenv` with env overrides.
4. Run `./tests/run.sh <description>` to verify.

Use the matching prefix for the hook you want to exercise (see table above).
