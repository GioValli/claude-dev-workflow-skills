---
name: change-workflow
description: Apply a 2-phase workflow to close every code change. Phase A (per self-contained change) pre-flight check, build, database migration audit, on-request demo and usage workflow for user-visible changes, CHANGELOG, user manual page (or README audit if the project has no manual), Conventional commit, push branch/PR by default or direct FF only for small fixes. Phase B (post-merge master) detects commits accumulated beyond the latest tag, proposes deploy, bumps version on confirmation, tags, pushes master --follow-tags, cleans up worktrees. Always checks parallel sessions (multiple worktrees) and migration revision id collisions. Use this skill on every code change, including minor ones, including long-running branches. Don't skip steps.
---

# Code change workflow

> **Shell convention** — On Windows + PowerShell, POSIX commands (`grep`, `find`, `xargs`, `uniq`, `sort`) don't work natively: run them with the Bash tool (git bash is available via WSL/Git for Windows). Commands like `Test-Path`, `Get-Date`, `Copy-Item` are PowerShell-only. Commands `git`/`gh`/`docker compose`/`npm` work in both. On Linux/macOS this distinction doesn't apply.

> **Placeholders** — This skill uses `<REPO_ROOT>` for the main repo path (typically `C:/Code/<repo>` on Windows or `~/code/<repo>` on Unix), `<GITHUB_OWNER>/<GITHUB_REPO>` for the remote repo, `<MIGRATIONS_DIR>` for your ORM's migrations folder (e.g. `backend/alembic/versions` for Alembic, `db/migrate` for Rails, `prisma/migrations` for Prisma), `<MANUAL_DIR>` for the project's user manual folder (Markdown pages + an `img/` subfolder, e.g. `docs/manual` or `frontend/public/manual-md`; the real path is stated in the project's `CLAUDE.md`/`AGENTS.md`). Adapt to your project paths.

This skill codifies the habit of closing every code change with a controlled mini-cycle, and of decoupling feature changes from release moments. The workflow has **two phases**:

- **Phase A** — for every self-contained change (feature/fix/refactor/docs). Run **end-to-end** before moving to the next task, even if the change seems small.
- **Phase B** — when `master`/`main` has changed (post-PR-merge or post-direct-FF) and there are commits beyond the latest tag. Run **only on explicit user confirmation** to propose/execute a release.

Key rule: **version bumps are NOT per-commit, NOT per-PR, NOT per-session-end**. They happen only in Phase B, when the user decides to release. Entries accumulate under `## [Unreleased]` in the CHANGELOG across one or more PRs from different sessions, and get closed into `## [X.Y.Z] - YYYY-MM-DD` only at release time.

## Phase A — Per self-contained change

### A0. Pre-flight check

Before touching any file:

1. `git status` → clean working tree (no rebase/merge/cherry-pick in progress). If there's a paused operation, **stop and notify the user**.
2. Current branch: must be `claude/*`, `feature/*` or equivalent. **Don't work directly on `master`/`main`**.
3. **Worktree isolation.** If the cwd is under `.../.claude/worktrees/<name>` but `git rev-parse --show-toplevel` is **not** under `.claude/worktrees/` (it resolves to the main repo), the session is **not isolated**: you're editing the shared main working tree, not a dedicated worktree. Not blocking, but from here on: (a) treat every edit/commit as landing on the shared tree, (b) with parallel sessions the branch can change under you → **re-verify `git branch --show-current` right before committing**, (c) commit only explicitly-staged files, **never `git add -A`** (you might sweep up other sessions' changes). (Note: comparing `--git-dir` with `--git-common-dir` is NOT reliable — one is absolute, the other relative.)
4. `git worktree list` → record other active worktrees.
5. For each other worktree: `git -C <path> status --short` + `git -C <path> diff origin/master --name-only`. If other worktrees modified `CHANGELOG.md`, files in `<MIGRATIONS_DIR>`, application version files (`package.json`, `pyproject.toml`, `Cargo.toml`, etc.) or `README.md` → **warn the user about conflict risk** (don't block).

### A1. Apply the change

Edit files. If the change spans multiple files, think of it as a single coherent logical change: all necessary files go into the same final commit.

### A2. Verify build/tests

Generic standards (adapt to your stack):

- Frontend touched → build command (`npm run build`, `yarn build`, `pnpm build`, etc.). Required. Failure = blocker.
- Backend touched → syntax + type check (`python -m compileall <dir>`, `mypy`, `tsc --noEmit`, etc.). Required. Failure = blocker.
- Targeted tests: only if the user asks or `CLAUDE.md`/`AGENTS.md` mentions them as required for every change.

The project's `CLAUDE.md`/`AGENTS.md` takes precedence over commands prescribed here.

### A3. Verify database migrations (if `<MIGRATIONS_DIR>` was touched)

Only if the change added/modified files in `<MIGRATIONS_DIR>`:

1. Verify there's **only one head**:
   - Alembic: `alembic heads` → expected **single line** like `<rev_id> (head)`
   - Rails: `rails db:migrate:status` → last applied migration
   - Prisma: `prisma migrate status`
2. Verify no duplicate revision id (Alembic example, run with the Bash tool):
   ```bash
   grep -h "^revision = " <MIGRATIONS_DIR>/*.py | sort | uniq -d
   ```
   Expected: **no output**. If output is non-empty, each line is a `revision = "..."` duplicated across files.

   To find WHICH files collide:
   ```bash
   grep -H "^revision = " <MIGRATIONS_DIR>/*.py | sort -t'"' -k2
   ```
   and visually identify lines with the same `revision = "..."`.
3. Cross-worktree check: for each other worktree seen in A0 with an added migration, verify your file's revision/id differs from theirs.
4. Linear `down_revision` chain (Alembic): `alembic history --verbose | head -50` for visual check.

**Collision resolution procedure** (happens when two parallel sessions add migrations on different branches):

- Identify the two files with duplicate ids
- Rename your file: `NNN_description.py` → `MMM_description.py` (increment to first free number)
- Update inside the file: `revision = "<new_id>"` and `down_revision = "<current_head_id>"`
- Verify with dry-run that the chain is valid (e.g. `alembic upgrade head --sql`)

### A3b. Demo and usage workflow (on request, user-visible changes only)

After build/tests (and applied migrations) and **before** CHANGELOG, commit and PR.

1. **Classify the change.**
   - **User-visible**: new/changed pages or screens, usage flows, permissions/roles, notifications, prints/exports, messages shown to the user.
   - **Internal**: calculations with no UI effect, tests, refactors, dependencies, documentation only, CI.
2. **Internal change** → no question. State it in the summary: *"Demo: not needed (internal change)."* Go to A4.
3. **User-visible change** → **ask** the user, with an explicit question, whether they want:
   - a **demo**: the app running locally on **fake data**, with real screenshots of the affected steps;
   - the step-by-step **usage workflow** (who does what, from which page, with what result).

   **Never assume yes**, even if the user has always accepted before: ask every time.
4. **On yes:**
   - start the app locally (commands from `CLAUDE.md`/`AGENTS.md`), load fake data (the project's seeds/fixtures or data created for the occasion), **never production data**;
   - show screenshots of the steps and write the step-by-step workflow;
   - **wait for explicit approval**. If the user asks for changes → back to A1, then repeat A2-A3b.
   - Keep the approved screenshots: they become the images of the manual page in A5.
5. **On no:** note it in the summary (*"Demo: declined by the user"*) and continue.

**The PR (A7) is opened only after the demo is approved**, when one was requested.

### A4. Update `CHANGELOG.md` (only `[Unreleased]`)

Under `## [Unreleased]`, add a concise entry. Group by category ([Keep a Changelog](https://keepachangelog.com/) format):

- `### Added` — new features/files/buttons/commands
- `### Changed` — behavior of something that already existed
- `### Fixed` — resolved bugs
- `### Removed` — things taken out
- `### Security` — security patches
- `### Docs` — user manual/README/CHANGELOG/docs updates (**custom category**, not standard Keep a Changelog — useful if manual, README and CHANGELOG are kept in sync)

Standard Keep a Changelog category not always used: `Deprecated` (skip if you have an aggressive release policy that removes directly in MAJOR versions).

Each entry is 1-2 lines: **what changed and why**, not how.

**Don't**: close `[Unreleased]` with a new version, touch version files (`package.json`, etc.), create tags. All that is Phase B.

### A5. User manual (and README audit for operational entries)

The **user manual** explains how features are used; the **README** stays for presentation, installation, deploy and configuration. A README that describes every feature grows endless and always lags behind: features go into the manual, one page per feature or area, with images.

**Where the manual lives.** The path is project-specific: read it from `CLAUDE.md`/`AGENTS.md` (here `<MANUAL_DIR>`). If the project **has no manual** (no mention and no obvious folder), skip point 1 and apply the README audit of point 2 to user-visible entries too (classic behavior: Features, Permissions, Notifications sections of the README).

Compare the just-added entries (and all those accumulated under `[Unreleased]`) against the manual and README:

1. **User-visible change → manual page.**
   - Update (or create) the `<MANUAL_DIR>` page describing the feature: what it's for, who can use it, the step-by-step workflow, any warnings. The workflow approved in A3b is the basis of the text.
   - Images in `<MANUAL_DIR>/img/`: the demo screenshots, **fake data only, never production** (no real names, emails, amounts or documents), **compressed** (optimized PNG or WebP/JPEG, reasonable width, ideally < 200 KB each), with descriptive names (`<feature>-<step>.png`). Without a demo, update at least the text and flag the missing images in the summary.
   - If the project has a page index (table of contents, menu, index file), add the entry.
   - Add an entry under `### Docs` of `[Unreleased]` ("Manual: page X — Y") and include page and images in the **same commit/PR** as the change.
   - Don't duplicate the feature description in the README: at most a link to the manual.
2. **Operational entry → README audit.** If README is not in context, read it with the Read tool. Classify:

   | Entry type | Where it goes | Typical section |
   |---|---|---|
   | New module / user-visible feature | Manual (README only if the project has no manual) | feature page |
   | New role / permissions change | Manual (README only if the project has no manual) | feature page / Permissions |
   | New notification type / channel | Manual (README only if the project has no manual) | Notifications page |
   | New env var / deploy change / new volume / new scheduler job | README | Deploy/Configuration |
   | Bug fix / refactor / internal migration / deps without user impact | none | — |

   If at least one entry is operational → update README sections, add an entry under `### Docs` ("README updated: section X — Y") and include `README.md` in the **same commit** as the feature.
3. If all entries are internal → state explicitly in chat: *"Manual and README: no update needed."*

Edge case: if the current change is "pure documentation" (typo in CHANGELOG/README/manual), skip this step.

### A6. Git commit

**Conventional Commits with scope**:

```
<type>(<scope>): <description>

[optional body]

Co-Authored-By: Claude <noreply@anthropic.com>
```

- Types: `feat`, `fix`, `docs`, `refactor`, `style`, `chore`, `test`
- Scope: module or area (`auth`, `api`, `frontend`, `db`, etc.)
- Description: ≤72 chars on first line
- Body: only when needed to explain "why" (blank line separator)
- `Co-Authored-By` signature recommended when Claude contributed

Operational rules:

- Explicit `git add` on touched files. **Never** `git add .` or `git add -A`.
- **Do not** use `--no-verify` to skip pre-commit hooks. If a hook fails, fix the root cause and create a **new** commit (not `--amend`).
- Multi-line via HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
feat(scope): description

Extended body if needed.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### A7. Push & integration with master

Push the current branch:

```bash
git push -u origin <current-branch>
```

Then decide: **PR** (default) or **direct FF** (exception).

#### Default: Pull Request

```bash
gh pr create --title "<type>(<scope>): <description>" --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Test
- [ ] Frontend build OK
- [ ] Backend syntax/type check OK
- [ ] (if applicable) migrations applied OK
- [ ] Demo: approved / not requested / not needed (internal change)
- [ ] User manual: page updated / not needed
- [ ] README audit (operational entries): done / not needed

EOF
)"
```

If the user asked for a demo in A3b, the PR is opened **only after** their explicit approval.

After the PR, **Phase B does not start** until the PR is merged.

#### Exception: direct FF branch:master

Allowed **only** if ALL these criteria hold:

- Single commit
- Type `fix(...)`, `docs(...)`, `chore(...)` or `style(...)` — **never** `feat(...)`
- Total diff ≤200 lines
- No files in `<MIGRATIONS_DIR>`
- No files in ORM models directory
- No files in `.github/workflows/` (modifying CI is what validates PRs — modifying it via FF is a circular risk)
- No added/removed dependencies
- No API breaking change
- No changes to deploy files (`docker-compose*.yml`, IaC, update scripts)

Even **one** violated → PR required.

If all hold, FF option:

```bash
git push origin <current-branch>:master --follow-tags
```

Server-side fast-forward, no merge commit. Local `master` of main repo stays behind (align in B5).

### When to apply Phase A

Key concept: **self-contained functional change** — a change with a complete meaning whose absence wouldn't break anything.

| Scenario | One commit or more? |
|---|---|
| Change a field in a form | **One** |
| Fix a wrong path in 4 files | **One** (same logical fix) |
| Add field: model + save + UI | **One** (same feature) |
| Feature + unrelated refactor | **Two** separate commits |
| Bug fix A + unrelated bug fix B | **Two** separate commits |

When in doubt, prefer more small commits over one big one.

### Exceptions & commit debt

Skip A4-A6 (CHANGELOG+commit) **only** if the user says so explicitly:

- **"don't commit yet"** → apply A1+A2, **record the debt** in chat ("Open commit debt: uncommitted changes to X. To close before end of session."), remind the user at end of session.
- **"don't commit at all" / "scrap it" / "throw it away"** → run `git restore .` only on files I modified. No debt recorded.
- **"let's test first"** → apply A1+A2, wait for test OK, then resume from A3.

## Phase B — When master changes (post-merge / post-FF)

### B0. Phase B trigger

Verify the phase applies (use `origin/master` as perspective, NOT HEAD — the current branch might not contain the latest tag):

```bash
git fetch origin master --tags
LATEST_TAG=$(git describe --tags --abbrev=0 origin/master)
git rev-list ${LATEST_TAG}..origin/master --count  # master commits beyond tag
```

If returns `0` → nothing to release, **don't propose deploy**.

If returns `≥1` → accumulated commits exist. Proceed to B1.

### B1. Show deploy info

Concisely present to the user:

```
Currently deployed version: vX.Y.Z (git tag)
Commits accumulated beyond tag: N
Latest title: <title of most recent commit>
[Unreleased] entries in CHANGELOG: <count + categories>
```

The deployed version comes from `git describe --tags --abbrev=0 origin/master`. If the app exposes a `/health` or `/version` endpoint, that's the primary source.

#### Edge case: `[Unreleased]` empty but N commits accumulated

Happens when accumulated commits are CI/chore only without user impact. Procedure:

1. Show the user the list of accumulated commits:
   ```bash
   git log ${LATEST_TAG}..origin/master --oneline
   ```
2. Ask: "No entries in `[Unreleased]`. Do you want to (a) skip the release, (b) generate CHANGELOG entries from commit titles, or (c) release anyway without entries?"
3. On (b): generate draft entries categorizing from prefixes `feat(...)/fix(...)/chore(...)`, show them to the user for confirmation before writing to CHANGELOG.
4. On (c): default PATCH bump, add a single `### Changed` entry with "Internal technical updates (see git log)".

### B2. Propose deploy

Explicit question:

> "Release with these N accumulated commits? Suggested bump: <PATCH/MINOR/MAJOR>"

**Never run B3-B4 without explicit user confirmation.** Even if the user said "always yes" before — deploy is an irreversible action with blast radius beyond the local machine.

If user says no → done, entries remain in `[Unreleased]` for the next deploy.

If yes → read `deploy.md` with the Read tool and follow B3 + B4.

### B5. Post-push cleanup

When the user signals end of session ("ok done", "we're finished", "thanks see you next time"), read `cleanup.md` with the Read tool and follow the 5 sub-steps. The final report is required even if there's nothing to clean.

## If the project has `CLAUDE.md` or `AGENTS.md`

If the repo root contains `CLAUDE.md` or `AGENTS.md`, read it **at session start**. Its content **takes precedence** over generic prescriptions of this skill (e.g. build commands, version files, commit scope conventions). This skill is the default; the project file is the truth.

## Why this workflow

- **Readable history**: each commit does one clear thing, `git log` tells the evolution without archaeology.
- **Surgical rollbacks**: `git revert` removes a change without touching the rest.
- **CHANGELOG always up-to-date**: at release time the document is ready.
- **Demo before the PR**: for user-visible changes the user sees real screenshots on fake data and approves before the PR exists.
- **User manual always aligned**: every user-visible feature updates its page, with images, in the same PR; the README stays short (presentation, installation, deploy, configuration).
- **Tracked parallel sessions**: multiple worktrees without silent collisions on CHANGELOG/migrations.
- **Bump at real deploy**: no phantom versions, tags match actual releases.
