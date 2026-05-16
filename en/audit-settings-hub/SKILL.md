---
name: audit-settings-hub
description: Verify and update the /settings admin hub when a code change adds new admin pages, new scheduler jobs, new admin-only table migrations, new adminOnly entries in workspace sidebars, or new routes under /admin/* or /settings/*. Decide whether you need a new entry in settingsNav.ts + route /settings/<area>/<item> + redirect from old URLs, or whether the change is internal and doesn't impact the hub. Run it as an additional step after A5 (README audit) of the change-workflow skill, whenever the change touches admin-visible files. Even for minor changes.
---

# Settings hub audit

> **Shell convention** — Commands `npm`, `npx`, `git mv` work in both shells (PowerShell and Bash). For `find/grep/xargs` use the Bash tool.

> **Use case** — This skill is written based on a real-world Italian project ("Jade", a small-business management system) with a `/impostazioni` hub gathering 8 admin areas. It's an **applied example**: principles are general (single source of truth for admin entries), but paths, area labels, and naming conventions need adapting to your project. If your settings hub uses a different name (`/admin`, `/control-panel`) or a different number of areas, adapt the "Reference architecture" and "Step 3" sections below.

This skill ensures the `/settings` hub (or equivalent in your project) remains the single source of truth for ALL admin functionality. When you add a new admin page, a new scheduler job, or touch a hub entry, run this audit to decide how to integrate it.

## When to apply

Automatic triggers — if ANY is true, run the audit:

| Trigger | Typically touched files |
|---|---|
| New admin-visible React page | `frontend/src/pages/admin/*.tsx`, `frontend/src/pages/settings/<area>/*Page.tsx` |
| New scheduler job (APScheduler, Celery, cron-equivalent) | `backend/app/jobs/*.py` or equivalent |
| New migration for an admin table (audit/config/system_settings) | your ORM's migrations folder |
| New admin route in the frontend router | `frontend/src/App.tsx` with paths `/admin/`, `/settings/`, `/users`, etc. |
| New `adminOnly: true` entry in workspace sidebars | `frontend/src/components/layout/Sidebar.tsx` |
| Removal/rename of an existing hub entry | `frontend/src/pages/settings/settingsNav.ts` |
| New admin-only REST endpoint | `backend/app/routers/admin_*.py` |

Don't run if the change is purely:
- Backend business logic (no new UI page)
- Non-admin frontend (operational workspaces: sales, inventory, etc.)
- Internal refactor of an existing page that does NOT change path or label

## Reference architecture (Jade example)

The Jade project's `/impostazioni` hub organizes all settings and admin pages into **8 areas**. The in-vivo source of truth is `frontend/src/pages/settings/settingsNav.ts` — if the number of areas changes, align this list:

| Area | URL slug | Scope |
|---|---|---|
| System | `system` | General, SSL, software updates, scheduled jobs, backup, trash, DB viewer |
| Users & Security | `users-and-security` | User management, audit log, privacy notice |
| Notifications | `notifications` | Channels, rules, digest, template previews, send log |
| Master data | `master-data` | Taxonomies, categories, role mappings, other categories |
| Integrations | `integrations` | External systems the app talks to (sync, credentials, tokens) |
| Tools & Maintenance | `tools` | Dedup, import, maintenance, operational audit, reports |
| App | `app` | Version history, app info |
| Digital signature | `signature` | Installed signatures, trust list, signable doc types |

**Single source of truth**: `frontend/src/pages/settings/settingsNav.ts` exports `SETTINGS_AREAS: SettingsArea[]`. From here it auto-generates:
- The `<SettingsSidebar>` (layout component)
- The `<SettingsHubPage>` (hub cards)
- Area-hub redirects in `App.tsx`

**Established conventions**:
- All routes under `/settings/<area>/<item>` are **admin-only** (`<ProtectedRoute adminOnly>`)
- No `adminOnly: true` entry should exist in workspace sidebars
- The ⚙ Settings button lives only in the fixed "System" section at the bottom of each workspace sidebar
- Standalone pages live in `frontend/src/pages/settings/<areaSlug>/<Name>Page.tsx`
- Files use PascalCase names (e.g. `UsersPage.tsx`, `CitiesPage.tsx`)
- React components export both `named` and `default` (named preferred for `App.tsx` import with alias)

## Audit steps

### Step 1: Classify the change

For each new/modified file, answer:

1. **Is it admin-visible?** (requires admin login to be viewed/used) → Yes/No
2. **Does an appropriate entry/area already exist in the hub?** → Identify which
3. **Adds new CRUD/audit/config/integration?** → Yes = new entry; No = maybe modifies existing

### Step 2: Decide the action

| Case | Action |
|---|---|
| New standalone admin page | Add entry to `SETTINGS_AREAS` (appropriate area) + route `/settings/<area>/<slug>` + move file to `pages/settings/<area>/` + redirect from old URL |
| New scheduler job | Decorate with the convention `tracked_job(job_id, fn, singleton=False)` (singleton=True if long-running) + add description to `JOB_DESCRIPTIONS` dict of the admin jobs router |
| New admin table migration | Just correct `down_revision` + verify no duplicate revision id (cross-worktree) |
| New admin REST endpoint | Verify it uses `Depends(require_admin)` and prefix `/api/v1/admin/<scope>` |
| `adminOnly` entry added to workspace sidebar | **Remove it**: all admin entries belong in `/settings`, no shortcuts in workspace sidebars |
| Existing page with cosmetic changes | Verify label in `settingsNav.ts` is still descriptive; update if needed |
| Internal page of operational module (non-admin) | Skip — doesn't concern the hub |

### Step 3: Pick the right area

Decision tree for new entries:

```
New admin entry → which area?

├─ System technical config (SSL, backup, debug, updates, jobs)
│  └─ System
│
├─ Identity/access/security audit
│  └─ Users & Security
│
├─ Email/SMS/notifications
│  └─ Notifications
│
├─ Configurable taxonomy (master data, categories, mappings)
│  └─ Master data
│
├─ External system the app talks to (sync, credentials, tokens)
│  └─ Integrations
│
├─ Manual maintenance operation (dedup, import, operational audit)
│  └─ Tools & Maintenance
│
├─ App information (versions, docs)
│  └─ App
│
├─ Digital signature / PDF/A / trust list
│  └─ Digital signature
│
└─ No area fits → propose a NEW area to the user before adding
```

### Step 4: Add/update entry

If you add a new entry, run in order:

1. **`settingsNav.ts`** — add item to the `items` array of the chosen area:
   ```typescript
   { slug: '<slug>', label: '<Displayed label>' }
   ```
   Slug in kebab-case. Label in sentence case.

2. **Move file** (if needed): from `pages/admin/XxxPage.tsx` or other path to `pages/settings/<area>/<Name>Page.tsx`. Update component name (PascalCase + `Page` suffix). Update relative imports (depth changed: `../../api` → `../../../api`).

3. **`App.tsx`** — add:
   ```tsx
   import { <Name>Page as <Area><Name>Page } from './pages/settings/<area>/<Name>Page'
   // ...
   <Route path="<area>/<slug>" element={<<Area><Name>Page />} />
   ```
   Plus redirect from old URL (if the page existed under `/admin/*`):
   ```tsx
   <Route path="/admin/<old>" element={<Navigate to="/settings/<area>/<slug>" replace />} />
   ```

4. **CHANGELOG.md** — entry under `[Unreleased]` → `### Added` (or `### Changed` if entry existed and changes label/area).

5. **README.md** (only if the entry is user-visible for external admins, e.g. backup/updates, NOT for internal audits) — update Features or Production section.

### Step 5: Cleanup workspace sidebar entries

If the user's original change added an admin entry to workspace sidebars, **remove it**. The `/settings` hub is the only allowed access for admin entries.

Exception: non-admin operational entries that live in the workspace for flow reasons (e.g. daily reports also visible to operators) stay in the workspace.

### Step 6: Build verification

```bash
cd frontend && npm run build
```

If TS error or build fail, stop and report.

## Application examples

### Example 1: new admin page to manage "External OAuth Providers"

Trigger: new file `pages/admin/OAuthProvidersPage.tsx`.

Audit:
1. Admin-visible? Yes
2. Appropriate area? **Integrations** (external system)
3. Action: add entry + move file

Execution:
- `settingsNav.ts`: add `{ slug: 'oauth-providers', label: 'External OAuth Providers' }` under Integrations
- `git mv pages/admin/OAuthProvidersPage.tsx pages/settings/integrations/OAuthProvidersPage.tsx`
- `App.tsx`: import + route `integrations/oauth-providers` + redirect from `/admin/oauth-providers`
- CHANGELOG entry

### Example 2: bug fix in an existing audit page (no new entry)

Trigger: modification to `pages/settings/tools/AuditPecPage.tsx`.

Audit:
1. Entry already in hub? Yes (`tools/audit-pec`)
2. Path or label changes? No
3. Action: skip — internal bug fix only

### Example 3: new scheduler job `cleanup_orphan_attachments`

Trigger: new `scheduler.add_job(cleanup_orphan_attachments, ..., id='cleanup_orphan_attachments')`.

Audit:
1. Decorate it with `tracked_job('cleanup_orphan_attachments', cleanup_orphan_attachments)` (no singleton — fast IO bound)
2. Add description in `JOB_DESCRIPTIONS` dict:
   ```python
   'cleanup_orphan_attachments': 'Cleanup orphan attachments without entity',
   ```
3. No new entry in settingsNav (the job appears automatically in `/settings/system/jobs`)

### Example 4: user adds `adminOnly: true` entry to workspace sidebar

Trigger: diff on `Sidebar.tsx` shows new entry with `adminOnly: true` in a workspace `*_NAV` array.

Audit:
1. Convention violated: no `adminOnly` entries in workspace sidebars
2. Action: remove the entry from NAV, integrate the target into `/settings/<area>/<item>` per Step 4

## Integration with change-workflow

This skill is an **additional step after A5** (README audit) of the `change-workflow` skill:

```
... A1 (change) → A2 (build) → A3 (migrations) → A4 (CHANGELOG) → A5 (README audit) → A5.5 (audit-settings-hub) → A6 (commit) → A7 (push/PR) ...
```

When in A5.5 you find entries to add/move, include them **in the same commit** as the original change. Do NOT make a separate commit for the settings audit: it's part of the feature.

Exception: if the audit identifies only workspace sidebar entry cleanup (Example 4), it can be a separate `refactor(settings): ...` commit because it's a convention correction, not part of the feature.

## Why this workflow

- **Single source of truth**: every admin entry has ONE access point, never duplicated
- **Discoverable**: the admin finds everything in one place, no "I just discovered this hidden page"
- **Automatic cleanup**: workspace sidebars stay clean, operational entries don't get polluted with admin features
- **Convention always applied**: no drift (e.g. a new `/admin/foo` entry left orphan, never linked)
- **Consistent history**: the CHANGELOG reflects where the entry truly lives, not where it was born
