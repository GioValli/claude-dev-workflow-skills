---
name: merge-pr
description: Close a Pull Request in a single operation: pre-merge check (mergeable, CI, review, branch up-to-date), merge commit via gh pr merge --delete-branch, post-merge cleanup (local master aligned + worktree/branch deleted), and Phase B proposal (version bump + tag + push master --follow-tags). Default merge commit (no squash/rebase) for consistency with PR history. Trigger with "merge the PR", "close PR #N", "do the merge", "merge it".
---

# merge-pr skill

> **Shell convention** — Commands `gh`, `git`, `docker compose` work in both shells (PowerShell and Bash). Commands with Unix pipes (`$(...)`, `|`, `xargs`) must be run with the Bash tool, not PowerShell.

> **Placeholders** — `<REPO_ROOT>` is the main repo path (e.g. `C:/Code/<repo>` on Windows). `<GITHUB_OWNER>/<GITHUB_REPO>` is the remote repo.

Close a Pull Request in a single operation: from pre-merge check up to the release tag on GitHub, stopping before the server deploy action (which stays manual or handled by external pipeline).

## M0. PR identification

Trigger: user says "merge the PR", "close PR #N", "do the merge", "merge it".

Identify the PR number:

1. If user specified a number (e.g. "merge #9") → use that.
2. Otherwise auto-detect from current branch:
   ```bash
   gh pr list --repo <GITHUB_OWNER>/<GITHUB_REPO> --head $(git -C <REPO_ROOT> branch --show-current) --json number --jq '.[0].number'
   ```
3. If there's no open PR for the current branch, **stop and notify the user**.

## M1. Pre-merge check

```bash
gh pr view <num> --repo <GITHUB_OWNER>/<GITHUB_REPO> --json number,state,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,isDraft,headRefName,baseRefName,title
```

Important semantic distinction (GitHub GraphQL API):

- `mergeable` ∈ {`MERGEABLE`, `CONFLICTING`, `UNKNOWN`} — only conflict presence/absence
- `mergeStateStatus` ∈ {`CLEAN`, `BEHIND`, `BLOCKED`, `DIRTY`, `HAS_HOOKS`, `UNKNOWN`, `UNSTABLE`} — overall merge state

Verify:

- `state == "OPEN"`. If `CLOSED`/`MERGED`, stop and notify.
- `isDraft == false`. If draft, ask user if they want `gh pr ready <num>` first.
- `mergeable != "CONFLICTING"`. If conflicting, flag with manual instructions (checkout branch + merge origin/master + resolve conflicts + push) and stop.
- `statusCheckRollup`: if it contains entries with `conclusion == "FAILURE"` → flag and stop. If it contains `status == "IN_PROGRESS"` → ask user whether to wait or force; **no polling**. If `[]` (no checks ran, can happen if PR doesn't trigger any workflow) → flag as anomaly but don't block.
- `reviewDecision`: ok if empty (no policy) or `APPROVED`. If `CHANGES_REQUESTED`, flag and stop.
- If `mergeStateStatus == "BEHIND"`: branch behind master. Propose `git -C <REPO_ROOT> fetch && git checkout <branch> && git pull --rebase origin master && git push --force-with-lease`, then re-run M1.
- If `mergeStateStatus == "BLOCKED"`: branch protection or required check not passing. Show the user the failing checks and stop.

Show the user a summary:

```
PR #N "<title>"
- State: OPEN
- Mergeable: <state>
- Review: <state or "no policy">
- CI: <count or "no checks">
Proceed with merge? (yes/no)
```

On `no`, stop. On `yes`, M2.

## M2. Execute merge

Default merge commit strategy:

```bash
gh pr merge <num> --repo <GITHUB_OWNER>/<GITHUB_REPO> --merge --delete-branch
```

`--delete-branch` deletes remote + local branch. Works even if the repo has `deleteBranchOnMerge: false`.

Alternative strategies (use only on explicit user request):
- `--squash` — squash all PR commits into one (loses intra-PR granularity)
- `--rebase` — rebase PR commits onto master (linear, loses merge commit)

**Caveat: merging others' PRs** — `gh pr merge --merge` works if you have write permissions on the repo, even if you're not the PR author.

Verify outcome:

```bash
gh pr view <num> --repo <GITHUB_OWNER>/<GITHUB_REPO> --json state,mergeCommit
```

Expected: `state == "MERGED"`, `mergeCommit.oid` populated. Otherwise, show the exact `gh pr merge` error and stop.

## M3. Post-merge cleanup

Read `cleanup.md` of the `change-workflow` skill with the Read tool, and apply the 5 sub-steps:

1. **B5.1 Align local master**: `git -C <REPO_ROOT> fetch origin --prune && git -C <REPO_ROOT> merge --ff-only origin/master`
2. **B5.2 Stop Docker containers** (if started in session)
3. **B5.3 Remove current worktree** (only if session closes here)
4. **B5.4 Audit stale worktrees** (no removal if ahead>0 or dirty)
5. **B5.5 Required final report**

The report also includes:

```
Merge PR #N: COMPLETED
- Merge commit: <SHA>
- Branch <name> deleted (remote + local)
- Local master aligned with origin/master
```

## M4. Phase B proposal (deploy)

Verify commits accumulated beyond the latest tag (perspective `origin/master`, not HEAD):

```bash
git -C <REPO_ROOT> fetch origin master --tags
LATEST_TAG=$(git -C <REPO_ROOT> describe --tags --abbrev=0 origin/master)
git -C <REPO_ROOT> rev-list ${LATEST_TAG}..origin/master --count
```

If returns `0` → report "No commits beyond latest tag, nothing to release" and done.

If `≥1`:

```bash
git -C <REPO_ROOT> log ${LATEST_TAG}..origin/master --oneline   # accumulated commits
```

Show the user:

```
Currently tagged version: vX.Y.Z
Commits accumulated beyond tag: N
Latest title: <title>
[Unreleased] entries in CHANGELOG: <count + categories>
Suggested bump: PATCH/MINOR/MAJOR

Release? (yes/no)
```

On `no` → done. Entries remain in `[Unreleased]`.

On `yes` → **read `deploy.md` of the `change-workflow` skill with the Read tool** and apply B3 + B4 from there. Do not duplicate steps here: `deploy.md` is the single source of truth for the bump + tag + push procedure, including the `[Unreleased]` empty edge case.

**Do not run deploy/ssh from Claude**. Applying to production stays manual for the IT admin or handled by CI/CD pipeline.

## Common errors and handling

| Error | Cause | Action |
|---|---|---|
| `gh: not authenticated` | gh token expired | Flag, suggest `gh auth login`, stop |
| `mergeable: CONFLICTING` | Conflicts with master | Show manual instructions, stop |
| `--delete-branch` fails | Branch has other open PRs | Show `gh` error, leave branch alive |
| `git merge --ff-only` fails | Untracked files colliding | Proceed as `cleanup.md` B5.1 (diff + `.local-backup`) |
| Tag push fails | Tag already exists / non-fast-forward | Show error, suggest `git fetch + rebase`, NO `--force` on master |

## Out of scope

- Polling/waiting on in-progress CI
- Automatic conflict resolution
- Automatic rollback
- External notifications (Slack/email)
- Server deploy (manual IT admin action)
- Version bump via PR (always direct on master)

## Why this skill

- Closes in one operation a flow that today requires GitHub UI + Claude + Claude (3 contexts)
- Maintains critical control: every destructive step (merge, bump) asks for explicit confirmation
- Automatically aligns local master with origin (no accumulated `behind`)
- Decouples "release published on GitHub" (Claude) from "applied to production" (manual IT admin)
