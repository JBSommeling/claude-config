# CPU-load guard

Hook: `.agents/hooks/block-cpu-load.sh` (PreToolUse, shell tool only).

## Purpose

An agent once ran a load test unattended and held an M3 Pro at about 95% CPU for 41 minutes. This hook
reduces the chance that an agent starts accidental, prolonged load, without getting in the way of normal
development. It is a best-effort filter over command text. It is not a sandbox and it cannot promise to
catch everything (see [Known limitations](#known-limitations)).

## Decision tiers

Order of precedence is deny, then ask, then allow. Every deny check runs before an ask is returned.

### Deny: synthetic burners with no legitimate development purpose

| What | Examples |
| --- | --- |
| Stress tools | `stress`, `stress-ng` |
| Busy loops that do nothing | `while true; do :; done`, `for ((;;)); do :; done`, `until false; do :; done` |
| Fork bombs | `:(){ :\|:& };:`, `function bomb { bomb \| bomb & }` |
| Discarded or hashed unbounded streams | `yes > /dev/null`, `yes \| gzip > /dev/null`, `cat /dev/urandom \| gzip > /dev/null`, `gzip < /dev/zero > /dev/null`, `sha256sum /dev/zero`, `dd if=/dev/zero of=/dev/null` |
| Inline interpreter infinite loops | `python3 -c 'while True: x=1'`, `node -e 'for(;;);'`, `ruby -e 'loop{}'`, `php -r 'while(true);'`, `perl -e '1 while 1'` (python, node, nodejs, deno, bun, ruby, perl, php with `-c`/`-e`/`-r`/`eval`), unless the code also contains `sleep`, `setTimeout`, `setInterval`, `await`, `input`, `read` or `break` |
| Unbounded parallelism | `make -j` with no number, `-j0`, `xargs -P 0`, `parallel -j 0` |
| CPU benchmarks | `openssl speed`, `sysbench cpu`, `7z b`, `7za b`, `geekbench*` |
| Crypto miners | `xmrig`, `cpuminer`, `minerd`, `ethminer`, `t-rex` |

The reason for denying: these exist only to burn cycles. No legitimate task needs them from an agent.

A random or zero stream counts as bounded when the same statement contains a `head` stage, `dd ... count=`
or `pv -S`/`--stop-at-size`. A bare `-c` or `-n` on a compressor is not a limit.

### Ask: ambiguous or legitimate-but-heavy work

The human approves each call.

- Load-test tools at command position: `k6`, `wrk`, `wrk2`, `ab`, `hey`, `vegeta`, `autocannon`, `siege`,
  `jmeter`, `locust`, `artillery`, `oha`, `bombardier`, `h2load`, `gatling`, `tsung`, `drill`, `ddosify`.
  Also via `npx`/`bunx`/`pnpx`, `yarn dlx`/`pnpm dlx`, and `docker|podman run` or `compose run` of an image or
  service named like one of them or like `stress`/`stress-ng`. Help and version invocations (`--help`, `-h`,
  `--version`, `-V`, `version`, `help`, `k6 inspect`) are allowed.
- Indirect execution whose name looks like a load job (see [Indirect detection](#indirect-detection)).
- Explicit parallelism above twice the core count: `make -jN`, `xargs -P N`, `parallel -j N`, `ninja -j N`,
  `cmake --build ... --parallel N`. The core count comes from `sysctl -n hw.ncpu` or `nproc`, default 8.
- Literal-infinite shell loops (`while true`, `while :`, `while [ 1 ]`, `until false`, `for ((;;))`) with a
  non-empty body that has no `sleep`, `wait`, `read` or `timeout`.

The reason for asking: these are often legitimate (a human may really want a load test), but they are the
exact shape of the incident, so a person should decide.

### Allow

Everything else, explicitly including unit and integration tests (`npm test`, `pytest -n auto`,
`vendor/bin/phpunit`, `php artisan test`, `go test ./...`, `cargo test`, `jest --maxWorkers=50%`), builds
(`make -j8`, `make -j$(nproc)`, `cargo build --release`, `npm run build`), dev servers (`npm run dev`,
`php artisan serve`), Docker (`docker compose up -d`, `docker build .`), migrations, polling loops with a
sleep, and `yes | apt-get install foo`.

Bounded microbenchmarks are allowed on purpose: `hyperfine`, `time make`, `cargo bench`,
`go test -bench=.`, `pytest --benchmark-only`. They finish on their own and are part of normal development.

## Command position

A tool name only counts when it is the command being run, so `echo "stress --cpu 8"` and
`grep -r stress .` stay allowed.

1. Newlines become `;` (backslash-newline continuations are joined first), then whitespace is collapsed.
2. A second view removes `'`, `"` and `\`, and all command matching runs on it. `bash -c "stress"`,
   `"stress"` and `st''ress` are therefore caught.
3. The text is split into statements on `; & && || ( ) { } !` and backticks (this includes `$(`), and each
   statement into pipeline stages on `|`.
4. Each stage drops leading wrappers, then the next word (path prefix removed) is the command.

Wrappers handled, in any number and order: `sudo`/`doas` (with `-u user` and similar), `nohup`, `exec`,
`command`, `builtin`, `time`, `setsid`, `env` (flags and `VAR=val`), bare `VAR=val` assignments,
`nice [-n N | -N]`, `timeout [-s SIG | -k D | --flags] DURATION`, `caffeinate`, `taskpolicy`, `ionice`,
`xargs`, `parallel`, `watch`, `bash|sh|zsh|dash|ksh -c`, `eval`, and the keywords `do then else elif if
while until !`. `command -v tool` is a lookup and is ignored.

## Indirect detection

When a stage is a runner, the hook resolves one level of what it would run and scans that text. Nothing is
executed, sourced or recursed into.

| Runner | Resolved from |
| --- | --- |
| `npm run X`, `npm run-script X`, `npm test/start/stop/restart`, `yarn X`, `yarn run X`, `pnpm X`, `pnpm run X`, `bun run X` | `scripts.X` (plus `preX` and `postX`) in `package.json` |
| `composer X`, `composer run-script X` | `scripts.X` in `composer.json`, string or array |
| `make X`, `gmake X` (each non-flag target) | the tab-indented recipe lines of that target, honouring `-C` and `-f` |
| `./path/to/file`, `bash\|sh\|zsh path/to/file` | the first 64 KiB of an existing regular file, comment lines dropped |
| `just X`, `task X`, `php artisan X` | name only |

The directory is the payload `cwd` (falling back to `$PWD`), adjusted by literal `cd dir` statements. The
filesystem is only touched when a runner is present.

Outcome for a resolved body or a runner name:

1. The body matches a deny-tier pattern or a load-test tool: deny, naming the script and the finding.
2. Otherwise, a script, target, artisan command or file name matching
   `(^|[-_:./])(bench|benchmark|benchmarks|loadtest|load-test|load_test|load:test|stress|stresstest|stress-test|perf-test|perftest|performance|soak|spike|burn|torture|flood)([-_:./]|$)`
   (case-insensitive): ask. The trailing class includes `/` so directory names like `benchmarks/` match.
3. Otherwise: allow.

Limits: only one level (a script that calls another script is not followed), only the first 64 KiB of a
file, and a file is read only if it exists. Parallelism asks and loop asks inside a resolved body are
ignored; only deny-tier findings and load-test tools count there.

## Platform and mode behaviour of ask

`hook_ask` in `lib/common.sh` emits a `permissionDecision` of `ask`. It fails closed to a deny, with the
reason prefixed `Needs human approval, which cannot be prompted here:`, when:

- the adapter does not support ask (`hook_supports_ask` is missing or fails; the Codex adapter returns 1);
- the payload `permission_mode` is `bypassPermissions` (behaviour of a hook ask there is undocumented, so
  it is treated as unable to prompt) or `dontAsk`.

In headless `-p` runs there is nobody to answer, so an ask cannot be approved there and effectively blocks
the call.

## Bypass

`CLAUDE_BYPASS_CPU_LOAD_GUARD=1` or `CODEX_BYPASS_CPU_LOAD_GUARD=1` skips every check, including the ask tier,
for that session.

## Performance

The hook runs on every shell call. A plain `git status` takes about 25 ms of wall time (median over 20 runs),
most of it process start-up and `jq`. Wrapper parsing only runs for stages whose first word could be a
wrapper, and the interpreter and loop checks are gated by a cheap keyword test.

## Known limitations

This is text matching. A determined or merely unlucky command can get past it.

- Variables and indirection: `t=stress; $t`, `$'\x73tress'`, base64 piped to `sh`, and `eval` of a
  computed string are not decoded.
- Scripts that call other scripts: only one level is resolved.
- Load generated by code: a test suite, app or script that loops internally looks like `npm test`.
- Load started by something already running: an existing process, or a dev server's file watcher, is not
  visible in the command that triggers it.
- Remote load: `ssh host 'stress ...'` is not inspected, and load aimed at a remote URL that loops back to
  localhost looks like a normal tool call (and is an ask only when it is a known tool).
- Compiled binaries with innocent names are allowed.
- Quoted-mention false positives: a quoted `;`, `|` or newline starts a new "statement", so a commit message
  or `echo` argument that contains `; stress --cpu 1`, or a multi-line message with a line that begins with a
  denied or load-tool word (`hey there`), is denied or asked. The hook cannot tell intent from context.
- Heredocs and comments inside resolved script bodies are scanned as code, except whole-line `#` comments.
- Parallel agents: several agents each running legitimate heavy work can saturate a machine together.

## Recommendation

The robust complement is a runtime load watchdog (sample the machine load and stop or warn on sustained
high CPU), not more regex. This hook prevents the common accidental starts, and a watchdog catches the rest.
