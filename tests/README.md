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
| `<name>.gitbranch` | Push fixtures only: which scratch-repo branch to run on — `feature` (default) or `default` |
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

## Push fixtures and `.gitbranch`

`block-push.sh` consults the currently checked-out branch when deciding whether to allow a push, so running push fixtures against the developer's real working tree produces results that vary with whatever branch they happen to have checked out — on `main`, two fixtures used to flip from the expected outcome to the opposite, producing spurious failures. To eliminate that dependency, `run.sh` builds a scratch git repo the first time any push fixture runs and removes it on exit. The scratch repo contains a `main` branch and an `implement-codex-adaption` branch but no remote, so `gh repo view` fails and `origin/HEAD` is absent; this causes `block-push.sh` to fall through to its local-branch scan, which deterministically resolves the default branch to `main` regardless of the developer's environment. A `.gitbranch` sidecar controls which branch is checked out before the fixture runs: `feature` selects `implement-codex-adaption`, `default` selects `main`, and an absent sidecar is treated as `feature`. Any unrecognised value is a loud ERROR that fails the fixture immediately — a harness that silently ran fixtures against the wrong branch would let them assert nothing useful.

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
4. For push fixtures, optionally create `tests/fixtures/<prefix>-<description>.gitbranch` containing `feature` or `default` to select the scratch-repo branch (defaults to `feature` when absent).
5. Run `./tests/run.sh <description>` to verify.

Use the matching prefix for the hook you want to exercise (see table above).

## Codex delegation fixture notes

`codex-delegation-permissive-default` — tests that an unidentified caller is allowed when
`CODEX_ENFORCE_DELEGATION` is not set. The hook returns `unknown` for the Codex caller, so the
delegation logic never runs; the permissive default takes effect. This is the allow path for an
unrecognised caller.

The corresponding deny path — strict enforcement via `CODEX_ENFORCE_DELEGATION=1` — is covered by
`codex-delegation-strict-deny`, which uses an `apply_patch` payload and expects `deny`.
