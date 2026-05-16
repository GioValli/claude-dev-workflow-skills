# Claude Dev Workflow Skills

> 🇮🇹 [Versione italiana di questo README](README.it.md)

A collection of [Claude Code](https://claude.com/claude-code) skills for closing code changes the disciplined way: pre-flight checks, builds, migration audits, CHANGELOG, commit, push, PR, release tagging, and worktree cleanup — all in one workflow.

Written from real-world use on a Python (FastAPI) + React (Vite) + PostgreSQL project. Generalized to fit other stacks: the principles apply whether you use Alembic, Rails, Prisma, npm, pnpm, cargo, or any other tooling.

Available in **English** (`en/`) and **Italian** (`it/`).

## What's inside

| Skill | What it does |
|---|---|
| **`change-workflow`** (IT: `workflow-modifiche`) | Two-phase workflow. Phase A closes each self-contained change (pre-flight → build → migrations → CHANGELOG → README audit → commit → push/PR). Phase B handles release (version bump → tag → push, on explicit confirmation). Includes `cleanup.md` (worktree cleanup on session end) and `deploy.md` (release procedure detail). |
| **`merge-pr`** | Closes a Pull Request in one operation: pre-merge check (mergeable / CI / review / branch up-to-date) → `gh pr merge --merge --delete-branch` → post-merge cleanup → Phase B proposal. |
| **`audit-settings-hub`** (IT: `audit-impostazioni`) | Applied case-study: keeps an admin settings hub as the single source of truth. Triggers on new admin pages, scheduler jobs, admin migrations, and workspace-sidebar `adminOnly` entries. Adapt the area/slug list to your project. |

## Why these skills

- **Readable history**: every commit does one clear thing.
- **Predictable releases**: version bumps happen only when the user says "ship it", never automatically per-commit or per-PR. Entries accumulate under `## [Unreleased]` until release.
- **No phantom versions**: git tags match actual GitHub releases.
- **Parallel session safety**: multiple worktrees without silent collisions on CHANGELOG / migrations / version files.
- **Required final reports**: post-merge cleanup always produces a written status, so you know whether worktrees were removed, branches deleted, master aligned.

## Installation

These skills install into `~/.claude/skills/<skill-name>/` (the location Claude Code reads from at session start).

### Windows (PowerShell)

```powershell
git clone https://github.com/<your-username>/claude-dev-workflow-skills.git
cd claude-dev-workflow-skills
.\install.ps1                # interactive: choose en or it
.\install.ps1 -Lang en       # non-interactive: English
.\install.ps1 -Lang it       # non-interactive: Italian
```

### macOS / Linux (Bash)

```bash
git clone https://github.com/<your-username>/claude-dev-workflow-skills.git
cd claude-dev-workflow-skills
./install.sh                 # interactive: choose en or it
./install.sh en              # non-interactive: English
./install.sh it              # non-interactive: Italian
```

The install scripts **copy** the skills into `~/.claude/skills/`. They do not overwrite existing skills by default — if you already have a skill with the same name, the script will prompt you.

### Manual install

If you prefer to avoid the script, just copy the skill folders manually:

```bash
cp -r en/change-workflow ~/.claude/skills/
cp -r en/merge-pr ~/.claude/skills/
cp -r en/audit-settings-hub ~/.claude/skills/  # optional, case study
```

Then start (or restart) a Claude Code session — the skills are loaded by name from the `SKILL.md` frontmatter.

## Usage

Once installed, the skills auto-activate based on triggers in their `description` fields:

- `change-workflow`: invoked whenever you finish a code change (typically with phrases like "let's commit", "close this", or simply at the end of an edit session — Claude picks it up automatically).
- `merge-pr`: trigger with "merge the PR", "close PR #N", "do the merge", "merge it".
- `audit-settings-hub`: auto-fires after A5 of `change-workflow` when admin-visible files are touched.

You can also invoke them explicitly via the `Skill` tool in Claude Code.

## Adapting to your project

The skills use placeholders like `<REPO_ROOT>`, `<GITHUB_OWNER>/<GITHUB_REPO>`, `<MIGRATIONS_DIR>`. To make Claude apply them to your project automatically, you have two options:

**Option A — Inline customization**: clone the repo, edit the skill files in `en/` (or `it/`) replacing the placeholders with your paths, then install.

**Option B — Project `CLAUDE.md` / `AGENTS.md`**: leave the skills generic and put project-specific info (paths, version files, build commands) in your project's `CLAUDE.md` (Claude Code) or `AGENTS.md` (Cursor / generic). The skills explicitly defer to those files when present.

Option B is recommended if you'll use these skills across multiple projects.

## Project structure

```
claude-dev-workflow-skills/
├── README.md                   ← you are here (English)
├── README.it.md                ← Italian version
├── LICENSE                     ← MIT
├── .gitignore
├── install.ps1                 ← Windows installer
├── install.sh                  ← macOS/Linux installer
├── en/
│   ├── change-workflow/
│   │   ├── SKILL.md            ← always loaded when skill activates
│   │   ├── cleanup.md          ← loaded on-demand at session end
│   │   └── deploy.md           ← loaded on-demand at release time
│   ├── merge-pr/
│   │   └── SKILL.md
│   └── audit-settings-hub/
│       └── SKILL.md
└── it/
    ├── workflow-modifiche/
    │   ├── SKILL.md
    │   ├── cleanup.md
    │   └── deploy.md
    ├── merge-pr/
    │   └── SKILL.md
    └── audit-impostazioni/
        └── SKILL.md
```

The split into `SKILL.md` + on-demand `.md` files is intentional: it follows Claude Code's **progressive disclosure** pattern. `SKILL.md` is loaded automatically when the skill is triggered; `cleanup.md` and `deploy.md` are loaded only when needed, keeping the context window lean during routine work.

## Compatibility

- **Claude Code** 1.0+ (skills system required)
- **Shell**: PowerShell 7+ on Windows; Bash on macOS/Linux. The skills explicitly note when a command is POSIX-only and must be run via the Bash tool on Windows.
- **Git**: 2.30+ (worktree commands)
- **GitHub CLI** (`gh`): required for `merge-pr` skill

## Contributing

PRs welcome. The skills are deliberately opinionated — they encode a specific workflow that works well for small teams and solo developers shipping to production servers without complex CI/CD pipelines. If your workflow differs significantly, consider forking rather than retrofitting.

When proposing changes:
- Keep `SKILL.md` files lean (≤300 lines). Push detail into on-demand `.md` files.
- Maintain feature parity between `en/` and `it/` versions.
- Update both `README.md` and `README.it.md` if you add/rename skills.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built with [Claude Code](https://claude.com/claude-code). Inspired by the [superpowers](https://github.com/anthropics/skills) skill framework patterns.
