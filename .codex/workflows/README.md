# Codex workflow overrides

Files placed here replace the corresponding file in `.agents/workflows/` when
`install.sh` installs for Codex.

For example, `.codex/workflows/ship.md` will be installed as
`~/.agents/skills/ship.md` instead of `.agents/workflows/ship.md`.

**This directory is a last resort.** Neutralize the shared copy in
`.agents/workflows/` wherever possible. Only drop an override here when a
workflow genuinely cannot be made platform-neutral without degrading its
usefulness on one of the platforms.
