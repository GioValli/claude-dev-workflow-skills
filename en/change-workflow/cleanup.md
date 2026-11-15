# change-workflow skill — Post-push cleanup detail (B5)

This file is loaded on-demand when, after push (A7) or deploy (B4), the user signals end of session ("ok done", "we're finished", "thanks see you next time", etc.). No mid-session cleanup.

Run all commands **from the main repo** (`<REPO_ROOT>`), not from the current worktree (it would be removed during the process). Use `git -C <main-repo>` with absolute paths.

## B5.1 Align local `master` to `origin/master`

```bash
git -C <REPO_ROOT> fetch origin --prune
git -C <REPO_ROOT> merge --ff-only origin/master   # if you're already on master in main repo
# otherwise: git -C <REPO_ROOT> checkout master && merge --ff-only origin/master
```

If FF fails due to **untracked files colliding** with incoming files from `origin/master`:

- Compare: `git -C <REPO_ROOT> show origin/master:<path> | diff - <full-disk-path>`
- If **identical** → delete the untracked copy (merge will recreate it)
- If **empty/irrelevant** → delete
- If **differs with uncommitted work** → rename with `.local-backup` suffix, complete FF, **flag in final report**

## B5.2 Stop local Docker containers (user preference)

If during the session Docker containers were started for smoke tests and the user is no longer manually testing:

```bash
docker compose -f <REPO_ROOT>/docker-compose.yml down
```

The same goes for servers started for the A3b demo (frontend/backend dev servers, test database with fake data): stop them if the user is no longer using them.

If local Docker was never started in the session, skip. Never touch production.

## B5.3 Remove the current worktree

```bash
git -C <REPO_ROOT> worktree remove --force <current-worktree-path>
git -C <REPO_ROOT> branch -d <current-branch>   # safe-delete
```

`branch -d` refuses the branch if not merged into master (anti-work-loss protection).

**Windows caveat**: sometimes `worktree remove` removes only git metadata but leaves the physical directory (files locked by IDE, Docker desktop, Windows indexer). Metadata is still clean. Flag in report: "Directory `<path>` to remove manually after closing IDE and shell."

**cwd caveat**: do NOT remove the current worktree while Claude's shell is inside that folder. Work with absolute paths and keep cwd elsewhere.

## B5.4 Audit stale worktrees and branches

```bash
git -C <REPO_ROOT> worktree list
git -C <REPO_ROOT> branch -vv
```

For each extra worktree:

```bash
git -C <wt-path> rev-list --count origin/master..HEAD   # commits beyond master
git -C <wt-path> merge-base --is-ancestor HEAD origin/master   # rc=0 yes, rc=1 no
git -C <wt-path> status --short   # uncommitted work
```

Classification:

- **ahead=0 + ancestor=yes + status clean** → removal candidate (proceed as B5.3, preserve any local `docs/`/spec/plan with `Copy-Item` first)
- **ahead>0** → **DO NOT remove**. Flag: N commits ahead, latest title
- **dirty status with real changes** → **DO NOT remove**. Flag

For local branches without a worktree: if ancestor of `origin/master` → `git branch -d`. Don't touch `feature/*`, `feat/*` branches — they belong to the user.

Wrap up:

```bash
git -C <REPO_ROOT> worktree prune
```

On Windows some prunes fail with "Permission denied" due to file locks: tolerable, flag.

## B5.5 Required final report

In the last session turn **always include** a cleanup section, even if nothing was cleaned:

```
Post-push cleanup:
- Local master aligned with origin/master (was behind by N commits)
- Current worktree <path> removed, branch <name> deleted
- Stale worktrees removed: <list>
- Worktrees with unmerged work (NOT removed): <list with N commits ahead, latest: <title>>
- Files preserved as backup: <list>.local-backup
- To remove manually (Windows file lock): <list>
- Local Docker: <stopped / never started>
```

Without this report the user doesn't know if cleanup succeeded.
