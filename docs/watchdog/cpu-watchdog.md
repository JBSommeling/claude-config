# CPU watchdog

Script: `.agents/watchdog/cpu-watchdog.sh` (macOS, run by launchd every 30 seconds).

## What it does

An agent once ran a load test unattended and held an M3 Pro at about 95% CPU for 41 minutes. The
[CPU-load guard hook](../hooks/block-cpu-load.md) screens command text before it runs, so it cannot see
load from test suites, scripts nested more than one level deep, compiled binaries or file watchers. The
watchdog is the runtime backstop: it measures the CPU that processes descending from agent sessions are
actually using, warns when it stays high, and then stops the heaviest job.

Each run is one stateless tick. State lives in `~/.claude/watchdog/state/`.

## Agent tree

- Roots are processes whose command basename is in `ROOT_NAMES` (default `claude codex`). Roots are never targets.
- Agent processes are all descendants of a root. Only processes owned by the current user are considered or signalled.
- A job is a direct child of a root together with its whole subtree. Job CPU is the sum of `ps` `pcpu` over that subtree.
- Nested roots (for example `codex` started by `claude`) own their own children.

## Thresholds and config

Config is `~/.claude/watchdog/config`, plain `KEY=value` lines (see `.agents/watchdog/config.example`). It is
parsed line by line and never sourced, so shell syntax in it has no effect. Unknown keys are ignored and
invalid values fall back to the default.

| Key | Default | Meaning |
| --- | --- | --- |
| `LOAD_FRACTION` | 0.75 | Agent total CPU at or above `ncpu*100*LOAD_FRACTION` counts as high. |
| `JOB_CORES` | 4 | A single job at or above `JOB_CORES*100` pcpu also counts as high. |
| `MACHINE_FRACTION` | 0.9 | Whole-machine pcpu (every process, every user) at or above `ncpu*100*MACHINE_FRACTION` is half of the machine condition (0 < x <= 1). |
| `MACHINE_AGENT_CORES` | 2 | The machine condition also needs agent total CPU at or above `MACHINE_AGENT_CORES*100` pcpu (1 or more, decimals allowed). |
| `WARN_AFTER` | 120 | Seconds of continuous high load before the warning notification. |
| `KILL_AFTER` | 300 | Seconds of continuous high load before the kill. |
| `MODE` | `kill` | `kill` or `notify`. |
| `ROOT_NAMES` | `claude codex` | Root process names. |
| `GRACE` | 10 | Seconds between SIGTERM and SIGKILL. |

Three conditions count as high load:

1. **Aggregate**: agent total CPU at or above `ncpu*100*LOAD_FRACTION`.
2. **Job**: one job at or above `JOB_CORES*100`.
3. **Machine**: the `pcpu` sum over every process in the same `ps` snapshot is at or above
   `ncpu*100*MACHINE_FRACTION` and the agent total is at or above `MACHINE_AGENT_CORES*100`. This catches
   the case where the user's own apps already use most of the machine, so a few agent jobs of 1 to 2 cores
   each pin it at 100% without tripping the other two rules. Both halves must hold: without a real agent
   share, busy user apps alone never trigger it, and non-agent processes are never signalled.

When the machine condition is high, the log line and notifications carry a summary such as
`machine=97% agents=4.6 cores`. It is tracked and escalated like the aggregate, and its kill target is the
heaviest eligible job.

"Continuous" means the state records the epoch when high load began and any tick below the threshold clears
it. The aggregate, the machine condition and each job (keyed by the root-child pid and its command) are tracked separately; the
longest-running high condition drives the warning and the kill.

## Actions

- **Warn** at `WARN_AFTER`: one macOS notification per episode naming the heaviest job (pid, command), its CPU and the elapsed time.
- **Kill** at `KILL_AFTER` with `MODE=kill`: SIGTERM to every process in the heaviest eligible job, deepest first, then a notification. One job per tick; the next tick re-evaluates.
- **SIGKILL** on a later tick: once `GRACE` seconds have passed since SIGTERM, any recorded pid that still exists with the same command gets SIGKILL. A job awaiting this check is not terminated again.
- **Notify mode**: at `KILL_AFTER` one extra notification per episode and no signals.

Safety checks before any signal: pid above 1, not the watchdog itself, a descendant of a root, owned by the
current user, and pid plus command match the recorded values (this guards against pid reuse; live runs
re-check against `ps` immediately before signalling). If `ps` fails or no roots exist, state is cleared and the
tick exits 0. The script always exits 0 at runtime so launchd does not throttle it.

## Pause switch

Create `~/.claude/watchdog/paused` to run a deliberate load test. While it exists the watchdog logs
"paused" at most once per hour, does nothing else and discards its timers. Remove the file to resume; the
clock starts fresh.

    touch ~/.claude/watchdog/paused
    rm ~/.claude/watchdog/paused

## Install and uninstall

`./install.sh --claude` installs it on macOS (skipped elsewhere and with `--no-watchdog`): the script and a
default config go to `~/.claude/watchdog/` (an existing config is kept), the plist is expanded into
`~/Library/LaunchAgents/com.claude-config.cpu-watchdog.plist` and loaded with `launchctl bootstrap`.
`~/.claude/watchdog` is not a `--clean` managed folder, so `--clean` never removes your config, state or log.

    launchctl bootout gui/$(id -u)/com.claude-config.cpu-watchdog
    rm ~/Library/LaunchAgents/com.claude-config.cpu-watchdog.plist

## Log

`~/.claude/watchdog/watchdog.log`: an ISO timestamp plus the event. When it passes about 1 MB it is cut to
its last 500 lines. launchd stderr goes to `~/.claude/watchdog/launchd.err`; at the start of each tick,
if that file is over 256 KB it is cut to its last 200 lines.

## Testing

`bash .agents/watchdog/tests/cpu-watchdog.test.sh` runs scenario tests against fixture `ps` snapshots with an
injected clock and `--dry-run`. `--dry-run` prints the intended actions (`ACTION SIGTERM ...`), sends no
signals or notifications, but still writes state and the log. Tests never generate load.

## Known limitations

- Load inside Docker Desktop's VM is not in the agent's process tree; only the `docker` CLI is.
- Daemons the agent asked to start (for example `brew services`) reparent to launchd and are not seen.
- `ps` `pcpu` is a decaying average, so spikes register late and fade slowly.
- Granularity is 30 seconds, so timings can overshoot by up to one interval.
- A process that double-forks away from the tree escapes.
