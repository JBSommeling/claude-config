---
name: initialize-repo
description: Bring a repository to the standard in REPO-STRUCTURE.md, or audit an already adopted repo for drift. Audits the repo read-only, presents a proposal (Repo profile, move table, tooling, changelog) for approval, then applies only the approved rows on a branch and opens a draft PR. Use when the user says "/initialize-repo", "initialize this repo", "adopt the repo structure", "set up context docs", "restructure the docs", or "audit the repo structure for drift".
---

# Initialize Repo

Bring a repo to the standard in [REPO-STRUCTURE.md](REPO-STRUCTURE.md), or audit an adopted repo for drift. That file holds every rule: layout, frontmatter, changelog, profile, platforms. This skill applies it and does not restate it.

## Hard limits

- Never deletes a file.
- Never moves code: application source, tests and build config stay where they are.
- Never rewrites document content. Moves, frontmatter and generated indexes only.
- Never works on the default branch.
- Changes nothing before the checkpoint is approved.

## Stage 1 — Audit (read-only)

### 1. Mode

Read `AGENTS.md` and `CLAUDE.md`. A `## Repo profile` section means **drift-audit mode**: compare the layout against the profile and the standard, run the four check scripts (step 6), report findings, and let the proposal contain fixes only. No profile means a first adoption.

### 2. Type and platforms

Guess the repo type and cite the evidence:

- Old application code alongside a new one: **migration**.
- No history, or an empty or new codebase: **greenfield**.
- An existing system evolving in place: **brownfield**.

Platforms: `claude` by default; `codex` when `.agents/` or `.codex/` tooling exists and `.claude/` does not; `both` when both exist. In drift-audit mode take both from the profile.

### 3. Inventory documentation

List every document the repo already has: README sections, `docs/`, `docs/adr/`, ADR-like files, `SPEC.md` or spec folders (and any `~/Desktop` specs the README mentions), `CONTEXT.md`, design system, UX principles, guidelines, meeting notes, release notes, `.claude/` and `.agents/` tooling, and existing scripts.

Map each to its target path per the Layout section of REPO-STRUCTURE.md. Migration repos use `context/target/...` for specs, standards and design system.

### 4. Changelog

Record whether a changelog exists and where. Variants to look for: `CHANGELOG.md`, `HISTORY.md`, `docs/CHANGELOG*`, `releases/`.

Busy-repo signal: three or more contributors in `git shortlog -sn --since=90.days`, or several open PRs (`gh pr list` when available). A busy repo gets the `changes/` fragments recommendation.

### 5. Gaps and conflicts

- **Gaps:** no glossary, no `AGENTS.md`, no specs, no `DECISIONS.md`.
- **Conflicts:** two documents that disagree, or a hand-written `README.md` inside a `context/` folder. Indexes own that filename, so the hand-written file must be renamed (for example `overview.md`) before indexes can be generated.

### 6. Run the checks (drift-audit mode)

Run each script with `--root <repo>`. Use the repo's `tools/` copy when present, otherwise the skill's `scripts/` folder:

```bash
python3 tools/build_index.py --check --root .
python3 tools/check_docs.py --root .
python3 tools/check_ids.py --root .
python3 tools/check_changelog.py --root . --base <default-branch>
```

Report every finding. Do not fix anything in this stage.

## Stage 2 — Proposal (checkpoint)

Present the proposal as numbered rows, and wait. The user approves, edits or rejects each row.

1. **Repo profile** to write, with the evidence for Type and Platforms. When `CLAUDE.md` exists without `@AGENTS.md`, add a row to insert that one line.
2. **Move table:** `# | current path | new path | reason`.
3. **Files it cannot place,** with the question that blocks each one.
4. **Changelog rows:** create a skeleton, `git mv` an existing file to the root, or record an override in the profile. Busy repos also get a `changes/` fragments row.
5. **Tooling rows:** copy the five scripts (`build_index.py`, `check_docs.py`, `check_ids.py`, `check_changelog.py`, `frontmatter.py`) into `tools/`. Copy `assets/docs-checks.yml` to `.github/workflows/` for GitHub repos only. For any other CI, print the four commands from step 6 for the user to wire by hand.
6. **Follow-ups it will NOT do:** content merges, writing missing docs, changelog backfill from tags, moving code.

In drift-audit mode the table holds only fixes for the findings. **Do not proceed without explicit approval.** Silence, or approval of only some rows, means only those rows.

## Stage 3 — Apply (approved rows only)

### 1. Branch

Invoke `/branch-preflight`. On the default branch, create a feature branch first. If preflight refuses or fails closed, stop.

### 2. Moves

Use `git mv` for every move so history follows the file. Never copy and delete.

### 3. Profile and entry files

- Write the Repo profile at the top of `AGENTS.md`. When `AGENTS.md` is missing, create it with the profile and a minimal repo map.
- Create `CLAUDE.md` containing `@AGENTS.md` when it is missing. When `CLAUDE.md` exists without the import, add the line only if that row was approved; never rewrite the rest of the file.

### 4. Frontmatter

For each moved context document without frontmatter, add the block from REPO-STRUCTURE.md: `title` from the first heading, known values filled in, unknown values left empty. Leave the body untouched.

### 5. Changelog

Create a Keep a Changelog skeleton (`# Changelog`, `## [Unreleased]`) when none exists, or `git mv` the existing file to the root. Do not create an empty `changes/` folder; document the fragment convention in `AGENTS.md` and let the first fragment create the folder.

### 6. Tooling

Copy the approved scripts into `tools/`, and the CI template when approved.

### 7. Indexes and checks

```bash
python3 tools/build_index.py
python3 tools/check_docs.py
python3 tools/check_ids.py
```

Report the results. Failures go into the PR description. Do not auto-fix document content to make a check pass.

### 8. Commit

Commit in logical groups: moves, profile and entry files, tooling, indexes. Run `git add` on named paths only.

### 9. Push and open a draft PR

Push (`--set-upstream origin <branch>` when no upstream exists). Write the PR body to a file, then detect the host as the full-pipeline Phase 5 does:

```bash
remote_host=$(git remote get-url origin | sed 's|^[a-z]*://||; s|^[^@]*@||; s|[:/].*||')
```

- `github.com`, or `gh auth status --hostname "$remote_host"` exits 0: `gh pr create --draft --title "$pr_title" --body-file "$pr_body_file"`.
- `dev.azure.com`, ends with `.visualstudio.com`, or `vs-ssh.visualstudio.com`: `az repos pr create --draft true --repository <repo-name> --source-branch <branch> --target-branch <default-branch> --title "$pr_title" --description "$pr_body"`, with `--organization` and `--project` unless defaults are configured.
- Any other host: stop and report.

Always `--draft`. Never mark the PR ready. Pass titles and bodies by file or variable, never interpolated into the command string.

The PR body holds the Repo profile, the move table, the check results, the follow-ups, and a final line `Docs: updated <paths>` (or `Docs: none needed: <reason>`).

## Re-running

The flow is identical. On an adopted repo the audit reports drift and the proposal contains only fixes. Rows already satisfied are not proposed again.
