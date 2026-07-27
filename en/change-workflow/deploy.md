# change-workflow skill — Phase B detail (deploy)

This file is loaded on-demand when entering **Phase B** (post-merge into master with commits beyond the latest tag, or explicit release request). Not loaded automatically with `SKILL.md`: read it with the Read tool only when needed.

**Important**: this skill's Phase B stops at pushing the tag to GitHub. Applying to production (e.g. `ssh + update.sh` on the server, Kubernetes deploy, CI/CD trigger) remains **manual or automated via external pipeline** — not managed by this skill.

## B3. Version bump

### B3.1 Decide PATCH/MINOR/MAJOR
Look at entries accumulated under `## [Unreleased]` in `CHANGELOG.md`:

- Only `### Fixed` and/or `### Docs` → **PATCH** (`X.Y.Z` → `X.Y.Z+1`)
- At least one `### Added` or `### Changed` → **MINOR** (`X.Y.Z` → `X.Y+1.0`)
- At least one `### Removed` or explicit breaking change → **MAJOR** (`X.Y.Z` → `X+1.0.0`)
- Only `### Security` → **PATCH** (unless user asks otherwise)

When in doubt, prefer PATCH. Ask user to confirm classification.

### B3.2 Version files to update
Identify all files containing the application version. Common examples:

- **Node.js/JS/TS**: `package.json` (`"version"` field)
- **Python**: `pyproject.toml` (`[project] version`), or constant in `__init__.py` / `main.py`
- **Rust**: `Cargo.toml` (`[package] version`)
- **Go**: typically a `version.go` with exported constant
- **Frontend duplicates**: `src/version.ts`, `src/constants.ts`, etc.

Verify with `Test-Path` (PowerShell) or `[ -f path ]` (Bash) before touching.

**Mandatory when present**: a `**Current version:** vX.Y.Z` banner at the top of `README.md`. Look for it (`grep -n "Current version\|Versione corrente" README.md`) and update it in the same release commit. It is the first fact anyone reads when opening the repo, and left outside the routine it goes stale silently: on a real repo it sat 30 releases behind.

### B3.3 Close `[Unreleased]` in CHANGELOG
Under `## [Unreleased]` (keeping `[Unreleased]` as empty header at top), add a new section `## [X.Y.Z] - YYYY-MM-DD` with all previously accumulated entries. Absolute today's date (`Get-Date -Format yyyy-MM-dd` on PowerShell, `date +%Y-%m-%d` on Bash).

### B3.4 Frontend build (if version is build-time injected)
If the version is injected at build time (e.g. Vite reads `package.json`, or `version.ts` is imported into the bundle), run the build. Wait for OK; if it fails, stop and report the error.

### B3.5 Commit "release vX.Y.Z" (directly on master, no PR)
Explicit `git add` on only the bump files:

```bash
git add <version-files> CHANGELOG.md
```

Include all version files actually modified. If `README.md` was also touched for the current version, include it.

Commit (consistent with typical history of direct-on-master release commits):

```bash
git commit -m "$(cat <<'EOF'
release vX.Y.Z

<one-line release summary>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### B3.6 Annotated tag
```bash
git tag -a vX.Y.Z -m "vX.Y.Z - <one-line summary>"
```

Verify: `git tag --sort=-v:refname | head -1` shows the just-created tag.

## B4. Push release to GitHub

### B4.1 Push master + tag
```bash
git push origin master --follow-tags
```

`--follow-tags` pushes only annotated tags reachable from the just-pushed commits.

If it fails for non-fast-forward: **DO NOT force**. `git fetch origin master`, check why remote master is ahead (likely another session merged in parallel), resolve, retry.

### B4.2 Final message to user
Show explicitly:

```
Release vX.Y.Z published on GitHub.

To apply in production (manual server action):
  <project-specific command, e.g. ssh user@host && cd /opt/<app> && bash update.sh>

The update script typically runs: git pull + build + restart + migrations.
Visually verify the app responds after update.
```

**Do not run ssh / deploy from Claude**. The user chooses when to apply (maintenance window, off-hours, etc.).

## Rollback (manual server procedure)

In case of post-update failure requiring quick rollback, instruct the user:

```bash
ssh user@<host>
cd /opt/<app>
git checkout vX.Y.Z-1   # previous tag
# rebuild/restart according to your stack
# if migration broke schema:
# alembic downgrade -1   (or equivalent for your ORM)
```

CHANGELOG entries should be reverted separately (manually or with a new commit `docs(changelog): revert ...`).

## Caveats and troubleshooting

- **Production build fails for OOM**: build locally + push pre-built image.
- **Migration fails in production**: read the error. If `Multiple head revisions`, it's a revision id collision (see A3 in main skill).
- **Tag created but push failed**: local tag remains. Don't delete without explicit request. Retry `git push --follow-tags` after resolving.
