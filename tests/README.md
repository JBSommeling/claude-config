# Hook Tests

Dependency-free test harness for the two PreToolUse hook scripts. Captures current behaviour as golden tests.

## Running

```bash
# Run all fixtures
./tests/run.sh

# Run only fixtures whose name contains a substring
./tests/run.sh delegation
./tests/run.sh push
./tests/run.sh quoted-gt
```

Exit code is 0 if all tests pass, 1 if any fail.

## How it works

Each fixture is a pair of files in `tests/fixtures/`:

| File | Contents |
|------|----------|
| `<name>.json` | The hook's stdin payload (the JSON the Claude hook system sends) |
| `<name>.expect` | Either `allow` or `deny` |

The fixture filename prefix determines which hook is exercised:

- `delegation-*` → `.agents/hooks/enforce-delegation.sh`
- `push-*` → `.agents/hooks/block-push-to-default-branch.sh`

## Decision rule

The runner pipes the JSON into the hook and inspects the result:

- **deny** — stdout contains `"permissionDecision": "deny"` (with or without spaces around the colon), OR the hook exits with code 2.
- **allow** — anything else (hook exits 0 with no deny in stdout, or exits 0 with no output).

`CLAUDE_BYPASS_DELEGATION=0` and `CLAUDE_BYPASS_PUSH_GUARD=0` are set explicitly when running hooks so the developer's own environment cannot skew results.

## Adding a fixture

1. Create `tests/fixtures/<prefix>-<description>.json` with the hook payload.
2. Create `tests/fixtures/<prefix>-<description>.expect` containing either `allow` or `deny`.
3. Run `./tests/run.sh <description>` to verify.

Use the `delegation-` prefix for `enforce-delegation.sh` and `push-` for `block-push-to-default-branch.sh`.
