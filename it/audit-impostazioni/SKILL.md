---
name: audit-impostazioni
description: Verifica e aggiorna il hub /impostazioni (o equivalente settings hub admin) quando una modifica al codice aggiunge nuove pagine admin, nuovi job scheduler, nuove migrazioni di tabelle admin-only, nuove voci adminOnly nelle sidebar workspace, o nuove route sotto /admin/* o /impostazioni/*. Decide se serve nuova voce in settingsNav.ts + route /impostazioni/<area>/<voce> + redirect dalle vecchie URL, oppure se la modifica è interna e non impatta il hub. Eseguila come step aggiuntivo dopo A5 (audit README) della skill workflow-modifiche, ogni volta che la modifica tocca file admin-visible. Anche per cambi minimi.
---

# Audit hub Impostazioni

> **Convenzione shell** — I comandi `npm`, `npx`, `git mv` funzionano in entrambe le shell (PowerShell e Bash). Per `find/grep/xargs` usare la Bash tool.

> **Caso d'uso** — Questa skill è scritta sulla base di un progetto reale (gestionale aziendale italiano "Jade") con un hub `/impostazioni` che raccoglie 8 aree admin. È un **esempio applicato**: i principi sono generali (single source of truth per le voci admin), ma path, label di aree e convenzioni di naming vanno adattati al tuo progetto. Se il tuo settings hub si chiama diversamente (`/admin`, `/settings`, `/control-panel`) o ha un numero diverso di aree, modifica le sezioni "Architettura di riferimento" e "Step 3" sotto.

Questa skill assicura che il hub `/impostazioni` (o equivalente nel tuo progetto) rimanga la single source of truth per TUTTE le funzionalità admin. Quando aggiungi una nuova pagina admin, un nuovo job scheduler o tocchi una voce del hub, esegui questo audit per decidere come integrarla.

## Quando applicarla

Trigger automatici — se UNO qualsiasi è true, esegui l'audit:

| Trigger | File tipicamente toccati |
|---|---|
| Nuova pagina React admin-visible | `frontend/src/pages/admin/*.tsx`, `frontend/src/pages/settings/<area>/*Page.tsx` |
| Nuovo job scheduler (APScheduler, Celery, cron-equivalente) | `backend/app/jobs/*.py` o equivalente |
| Nuova migration di tabella admin (audit/config/system_settings) | cartella migrazioni del tuo ORM |
| Nuova route admin nel router frontend | `frontend/src/App.tsx` con path `/admin/`, `/impostazioni/`, `/users`, ecc. |
| Nuova voce `adminOnly: true` nelle sidebar workspace | `frontend/src/components/layout/Sidebar.tsx` |
| Rimozione/rinomina di voce esistente del hub | `frontend/src/pages/settings/settingsNav.ts` |
| Nuovo endpoint REST admin-only | `backend/app/routers/admin_*.py` |

Non eseguire se la modifica è puramente:
- Backend business logic (nessuna pagina UI nuova)
- Frontend non-admin (workspace operativi: vendite, magazzino, ecc.)
- Refactor interno di una pagina esistente che NON cambia path o label

## Architettura di riferimento (esempio Jade)

Il hub `/impostazioni` del progetto Jade organizza tutte le impostazioni e pagine admin in **8 aree**. La fonte di verità in vivo è `frontend/src/pages/settings/settingsNav.ts` — se il numero di aree cambia, allinea questo elenco:

| Area | Slug URL | Scope |
|---|---|---|
| Sistema | `sistema` | Generale, SSL, aggiornamenti software, job programmati, backup, cestino, DB viewer |
| Utenti & Sicurezza | `utenti-e-sicurezza` | Gestione utenti, audit log, informativa privacy |
| Notifiche | `notifiche` | Canali, regole, digest, anteprime modelli, log invii |
| Anagrafiche | `anagrafiche` | Comuni, categorie, mapping ruoli, altre categorie |
| Integrazioni | `integrazioni` | Sistemi esterni con cui dialoga l'app (sync, credenziali, token) |
| Strumenti & Manutenzione | `strumenti` | Deduplica, import, manutenzione, audit operativo, report |
| App | `app` | Cronologia versioni, info applicazione |
| Firma digitale | `firma` | Firme installate, trust list, tipi doc. firmabili |

**Single source of truth**: `frontend/src/pages/settings/settingsNav.ts` esporta `SETTINGS_AREAS: SettingsArea[]`. Da qui si genera automaticamente:
- La `<SettingsSidebar>` (componente layout)
- La `<SettingsHubPage>` (cards dell'hub)
- I redirect area-hub in `App.tsx`

**Convenzioni stabilite**:
- Tutte le rotte sotto `/impostazioni/<area>/<voce>` sono **admin-only** (`<ProtectedRoute adminOnly>`)
- Nessuna voce `adminOnly: true` deve esistere nelle sidebar workspace
- Il bottone ⚙ Impostazioni vive solo nella sezione "Sistema" fissa in fondo a ciascuna sidebar workspace
- Le pagine standalone vivono in `frontend/src/pages/settings/<areaSlug>/<NomeIta>Page.tsx`
- I file usano nomi italiani PascalCase (es. `UtentiPage.tsx`, `ComuniPage.tsx`)
- I componenti React esportano sia `named` che `default` (named è preferito per import in `App.tsx` con alias)

## Step di audit

### Step 1: Classifica la modifica

Per ogni file nuovo/modificato, rispondi:

1. **È admin-visible?** (richiede login admin per essere visualizzata/usata) → Sì/No
2. **Esiste già una voce/area appropriata nel hub?** → Identifica quale
3. **Aggiunge nuovo CRUD/audit/config/integrazione?** → Sì = nuova voce; No = forse modifica esistente

### Step 2: Decidi l'azione

| Caso | Azione |
|---|---|
| Nuova pagina admin standalone | Aggiungi voce a `SETTINGS_AREAS` (area appropriata) + route `/impostazioni/<area>/<slug>` + sposta il file in `pages/settings/<area>/` + redirect dalla vecchia URL |
| Nuovo job scheduler | Decora con la convenzione `tracked_job(job_id, fn, singleton=False)` (singleton=True se long-running) + aggiungi descrizione in `JOB_DESCRIPTIONS` dict del router admin jobs |
| Nuova migration di tabella admin | Solo `down_revision` corretto + verifica nessun duplicato revision id (cross-worktree) |
| Nuovo endpoint REST admin | Verifica che usi `Depends(require_admin)` e prefix `/api/v1/admin/<scope>` |
| Voce adminOnly aggiunta a sidebar workspace | **Rimuovila**: tutte le voci admin vanno in `/impostazioni`, niente shortcut nelle sidebar workspace |
| Pagina esistente con modifiche cosmetiche | Verifica label in `settingsNav.ts` sia ancora descrittivo; aggiorna se serve |
| Pagina interna del modulo operativo (non admin) | Skip — non riguarda il hub |

### Step 3: Scegli l'area giusta

Decision tree per nuove voci:

```
Nuova voce admin → quale area?

├─ Config tecnica del sistema (SSL, backup, debug, aggiornamenti, job)
│  └─ Sistema
│
├─ Identità/accesso/audit di sicurezza
│  └─ Utenti & Sicurezza
│
├─ Email/SMS/notifiche
│  └─ Notifiche
│
├─ Tassonomia configurabile (anagrafiche, categorie, mapping)
│  └─ Anagrafiche
│
├─ Sistema esterno con cui l'app dialoga (sync, credenziali, token)
│  └─ Integrazioni
│
├─ Operazione manuale di manutenzione (deduplica, import, audit operativo)
│  └─ Strumenti & Manutenzione
│
├─ Informazioni sull'app (versioni, doc)
│  └─ App
│
├─ Firma digitale / PDF/A / trust list
│  └─ Firma digitale
│
└─ Nessuna area calza → proponi una NUOVA area all'utente prima di aggiungere
```

### Step 4: Aggiungi/aggiorna voce

Se aggiungi una nuova voce, esegui in ordine:

1. **`settingsNav.ts`** — aggiungi item all'array `items` dell'area scelta:
   ```typescript
   { slug: '<slug>', label: '<Label visualizzato>' }
   ```
   Slug in kebab-case. Label in italiano case sentence.

2. **Sposta file** (se necessario): da `pages/admin/XxxPage.tsx` o altro path a `pages/settings/<area>/<NomeIta>Page.tsx`. Aggiorna nome componente (PascalCase italiano + suffisso `Page`). Aggiorna import relativi (depth cambiata: `../../api` → `../../../api`).

3. **`App.tsx`** — aggiungi:
   ```tsx
   import { <Nome>Page as <Area><Nome>Page } from './pages/settings/<area>/<Nome>Page'
   // ...
   <Route path="<area>/<slug>" element={<<Area><Nome>Page />} />
   ```
   Più redirect dalla vecchia URL (se la pagina esisteva sotto `/admin/*`):
   ```tsx
   <Route path="/admin/<old>" element={<Navigate to="/impostazioni/<area>/<slug>" replace />} />
   ```

4. **CHANGELOG.md** — voce sotto `[Unreleased]` → `### Aggiunte` (o `### Modifiche` se la voce esisteva e cambia label/area).

5. **README.md** (solo se la voce è user-visible per admin esterni, es. backup/aggiornamenti, NON per audit interni) — aggiorna sezione Funzionalità o Produzione.

### Step 5: Cleanup voci sidebar workspace

Se la modifica originale dell'utente aveva aggiunto una voce admin alle sidebar workspace, **rimuovila**. Il hub `/impostazioni` è l'unico accesso ammesso per voci admin.

Eccezione: voci operative non-admin che vivono nel workspace per ragioni di flusso (es. report giornalieri visibili anche da operatori) restano nel workspace.

### Step 6: Verifica build

```bash
cd frontend && npm run build
```

Se TS error o build fail, fermati e riporta.

## Esempi di applicazione

### Esempio 1: nuova pagina admin per gestire "Provider OAuth esterni"

Trigger: nuovo file `pages/admin/OAuthProvidersPage.tsx`.

Audit:
1. Admin-visible? Sì
2. Area appropriata? **Integrazioni** (sistema esterno)
3. Azione: aggiungi voce + sposta file

Esecuzione:
- `settingsNav.ts`: aggiungi `{ slug: 'oauth-providers', label: 'Provider OAuth esterni' }` sotto Integrazioni
- `git mv pages/admin/OAuthProvidersPage.tsx pages/settings/integrazioni/OAuthProvidersPage.tsx`
- `App.tsx`: import + route `integrazioni/oauth-providers` + redirect da `/admin/oauth-providers`
- CHANGELOG entry

### Esempio 2: fix bug in una pagina audit esistente (nessuna nuova voce)

Trigger: modifica a `pages/settings/strumenti/AuditPecPage.tsx`.

Audit:
1. Voce già esistente nel hub? Sì (`strumenti/audit-pec`)
2. Cambia path o label? No
3. Azione: skip — solo bug fix interno

### Esempio 3: nuovo job scheduler `cleanup_orphan_attachments`

Trigger: nuovo `scheduler.add_job(cleanup_orphan_attachments, ..., id='cleanup_orphan_attachments')`.

Audit:
1. Decoralo con `tracked_job('cleanup_orphan_attachments', cleanup_orphan_attachments)` (no singleton — è IO bound veloce)
2. Aggiungi descrizione in `JOB_DESCRIPTIONS` dict:
   ```python
   'cleanup_orphan_attachments': 'Pulizia allegati orfani senza entity',
   ```
3. Niente nuova voce in settingsNav (il job appare automaticamente in `/impostazioni/sistema/job`)

### Esempio 4: utente aggiunge voce `adminOnly: true` a sidebar workspace

Trigger: diff su `Sidebar.tsx` mostra nuova voce con `adminOnly: true` in un array `*_NAV` di workspace.

Audit:
1. Convenzione violata: niente voci adminOnly nelle sidebar workspace
2. Azione: rimuovi la voce dal NAV, integra il target in `/impostazioni/<area>/<voce>` come da Step 4

## Integrazione con workflow-modifiche

Questa skill è uno **step aggiuntivo dopo A5** (audit README) della skill `workflow-modifiche`:

```
... A1 (modifica) → A2 (build) → A3 (alembic) → A4 (CHANGELOG) → A5 (audit README) → A5.5 (audit-impostazioni) → A6 (commit) → A7 (push/PR) ...
```

Quando in A5.5 trovi voci da aggiungere/spostare, includile **nello stesso commit** della modifica originale. NON fare un commit separato per l'audit impostazioni: è parte integrante della feature.

Eccezione: se l'audit identifica solo cleanup di voci sidebar workspace (Esempio 4), può essere un commit separato di tipo `refactor(impostazioni): ...` perché è una correzione di convenzione, non parte della feature.

## Perché questo workflow

- **Single source of truth**: ogni voce admin ha UN punto di accesso, mai duplicato
- **Discoverable**: l'admin trova tutto in un posto, niente "ho appena scoperto questa pagina nascosta"
- **Cleanup automatico**: le sidebar workspace restano pulite, le voci operative non si sporcano con feature admin
- **Convenzione applicata sempre**: niente derive (es. una nuova voce `/admin/foo` rimasta orfana mai linkata)
- **Cronologia coerente**: il CHANGELOG riflette dove la voce vive davvero, non dove era nata
