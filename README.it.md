# Claude Dev Workflow Skills

> 🇬🇧 [English version of this README](README.md)

Una raccolta di skill per [Claude Code](https://claude.com/claude-code) per chiudere modifiche al codice in modo disciplinato: pre-flight check, build, audit migrazioni, CHANGELOG, commit, push, PR, tag di release e cleanup worktree — tutto in un unico workflow.

Scritte sulla base dell'uso reale in un progetto Python (FastAPI) + React (Vite) + PostgreSQL. Generalizzate per adattarsi ad altri stack: i principi valgono che tu usi Alembic, Rails, Prisma, npm, pnpm, cargo o qualsiasi altro tooling.

Disponibili in **inglese** (`en/`) e **italiano** (`it/`).

## Cosa contiene

| Skill | Cosa fa |
|---|---|
| **`workflow-modifiche`** (EN: `change-workflow`) | Workflow a due fasi. Fase A chiude ogni modifica autocontenuta (pre-flight → build → migrazioni → demo e workflow d'uso su richiesta per le modifiche visibili → CHANGELOG → pagina del manuale d'uso con immagini, oppure audit README per le voci operative / i progetti senza manuale → commit → push/PR). Fase B gestisce il rilascio (bump versione → tag → push, su conferma esplicita). Include `cleanup.md` (pulizia worktree a fine sessione) e `deploy.md` (dettaglio procedura release). |
| **`merge-pr`** | Chiude una Pull Request in una operazione: pre-merge check (mergeable / CI / review / branch up-to-date) → `gh pr merge --merge --delete-branch` → cleanup post-merge → proposta Fase B. |
| **`audit-impostazioni`** (EN: `audit-settings-hub`) | Caso d'uso applicato: mantiene un hub Impostazioni admin come single source of truth. Trigger automatici su nuove pagine admin, job scheduler, migrazioni admin, voci `adminOnly` nelle sidebar workspace. Adatta la lista area/slug al tuo progetto. |

## Perché queste skill

- **Storico leggibile**: ogni commit fa una cosa chiara.
- **Release prevedibili**: il bump di versione avviene solo quando l'utente dice "rilascia", mai automaticamente per-commit o per-PR. Le voci si accumulano sotto `## [Unreleased]` fino al rilascio.
- **Demo prima della PR, manuale al posto di un README infinito**: per le modifiche visibili l'agente chiede se vuoi una demo su dati fittizi e il workflow d'uso, e apre la PR solo dopo la tua approvazione; le schermate approvate diventano una pagina del manuale d'uso del progetto, mentre il README resta per presentazione, installazione, deploy e configurazione.
- **Niente versioni fantasma**: i tag git corrispondono a release reali su GitHub.
- **Sicurezza in sessioni parallele**: più worktree senza collisioni silenti su CHANGELOG / migrazioni / file di versione.
- **Report finali obbligatori**: il cleanup post-merge produce sempre un report scritto, così sai se i worktree sono stati rimossi, i branch eliminati, il master allineato.

## Installazione

Le skill si installano in `~/.claude/skills/<skill-name>/` (il path da cui Claude Code le legge all'avvio della sessione).

### Windows (PowerShell)

```powershell
git clone https://github.com/<tuo-username>/claude-dev-workflow-skills.git
cd claude-dev-workflow-skills
.\install.ps1                # interattivo: scegli en o it
.\install.ps1 -Lang en       # non-interattivo: inglese
.\install.ps1 -Lang it       # non-interattivo: italiano
```

### macOS / Linux (Bash)

```bash
git clone https://github.com/<tuo-username>/claude-dev-workflow-skills.git
cd claude-dev-workflow-skills
./install.sh                 # interattivo: scegli en o it
./install.sh en              # non-interattivo: inglese
./install.sh it              # non-interattivo: italiano
```

Gli script di install **copiano** le skill in `~/.claude/skills/`. Di default non sovrascrivono skill esistenti — se hai già una skill con lo stesso nome, lo script ti chiederà conferma.

### Install manuale

Se preferisci evitare lo script, copia direttamente le cartelle:

```bash
cp -r it/workflow-modifiche ~/.claude/skills/
cp -r it/merge-pr ~/.claude/skills/
cp -r it/audit-impostazioni ~/.claude/skills/  # opzionale, caso d'uso
```

Poi avvia (o riavvia) una sessione Claude Code — le skill vengono caricate per nome dal frontmatter di `SKILL.md`.

## Utilizzo

Una volta installate, le skill si auto-attivano in base ai trigger nei loro campi `description`:

- `workflow-modifiche`: invocata ogni volta che chiudi una modifica al codice (tipicamente con frasi come "committiamo", "chiudi questa", o semplicemente a fine sessione di editing — Claude la rileva automaticamente).
- `merge-pr`: triggera con "merge la PR", "chiudi la PR #N", "fai il merge", "mergiala".
- `audit-impostazioni`: si attiva automaticamente dopo A5 di `workflow-modifiche` quando vengono toccati file admin-visible.

Puoi anche invocarle esplicitamente tramite la tool `Skill` di Claude Code.

## Adattare al tuo progetto

Le skill usano placeholder come `<REPO_ROOT>`, `<GITHUB_OWNER>/<GITHUB_REPO>`, `<MIGRATIONS_DIR>`. Per far sì che Claude le applichi al tuo progetto automaticamente, hai due opzioni:

**Opzione A — Customizzazione inline**: clona la repo, edita i file skill in `it/` (o `en/`) sostituendo i placeholder con i tuoi path, poi installa.

**Opzione B — `CLAUDE.md` / `AGENTS.md` del progetto**: lascia le skill generiche e metti le info specifiche del progetto (path, file di versione, comandi di build) nel `CLAUDE.md` (Claude Code) o `AGENTS.md` (Cursor / generico) del tuo progetto. Le skill rinviano esplicitamente a questi file quando presenti.

L'Opzione B è raccomandata se userai queste skill su più progetti.

## Struttura del progetto

```
claude-dev-workflow-skills/
├── README.md                   ← versione inglese
├── README.it.md                ← sei qui (italiano)
├── LICENSE                     ← MIT
├── .gitignore
├── install.ps1                 ← installer Windows
├── install.sh                  ← installer macOS/Linux
├── en/
│   ├── change-workflow/
│   │   ├── SKILL.md            ← sempre caricato quando la skill si attiva
│   │   ├── cleanup.md          ← caricato on-demand a fine sessione
│   │   └── deploy.md           ← caricato on-demand al momento del rilascio
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

La divisione `SKILL.md` + file `.md` on-demand è voluta: segue il pattern **progressive disclosure** di Claude Code. `SKILL.md` viene caricato automaticamente quando la skill è triggered; `cleanup.md` e `deploy.md` sono caricati solo quando servono, mantenendo snello il context window durante il lavoro di routine.

## Compatibilità

- **Claude Code** 1.0+ (sistema skill richiesto)
- **Shell**: PowerShell 7+ su Windows; Bash su macOS/Linux. Le skill segnalano esplicitamente quando un comando è POSIX-only e va eseguito tramite la Bash tool su Windows.
- **Git**: 2.30+ (comandi worktree)
- **GitHub CLI** (`gh`): richiesto per la skill `merge-pr`

## Contribuire

PR benvenute. Le skill sono deliberatamente opinionate — codificano un workflow specifico che funziona bene per team piccoli e sviluppatori solitari che rilasciano in produzione su server senza pipeline CI/CD complesse. Se il tuo workflow è significativamente diverso, considera un fork piuttosto che un retrofit.

Quando proponi modifiche:
- Mantieni i file `SKILL.md` snelli (≤300 righe). Sposta i dettagli in file `.md` on-demand.
- Mantieni parità di feature tra le versioni `en/` e `it/`.
- Aggiorna sia `README.md` che `README.it.md` se aggiungi/rinomini skill.

## Licenza

MIT — vedi [LICENSE](LICENSE).

## Crediti

Costruite con [Claude Code](https://claude.com/claude-code). Ispirate ai pattern del framework skill [superpowers](https://github.com/anthropics/skills).
