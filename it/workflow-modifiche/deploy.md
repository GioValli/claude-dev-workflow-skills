# Skill workflow-modifiche — Dettaglio Fase B (deploy)

Questo file è caricato on-demand quando entri in **Fase B** (post-merge in master con commit oltre il tag più recente, oppure richiesta esplicita di rilascio). Non è caricato automaticamente con `SKILL.md`: leggilo con la tool Read solo quando serve.

**Importante**: la Fase B di questa skill si ferma al push del tag su GitHub. L'applicazione in produzione (es. `ssh + update.sh` sul server, deploy Kubernetes, CI/CD trigger) resta **manuale o automatica via pipeline esterna** — non viene gestita da questa skill.

## B3. Bump versione

### B3.1 Decidi PATCH/MINOR/MAJOR
Guarda le voci accumulate sotto `## [Unreleased]` in `CHANGELOG.md`:

- Solo `### Fix` e/o `### Documentazione` → **PATCH** (`X.Y.Z` → `X.Y.Z+1`)
- Almeno una `### Aggiunte` o `### Modifiche` → **MINOR** (`X.Y.Z` → `X.Y+1.0`)
- Almeno una `### Rimozioni` o breaking change esplicito → **MAJOR** (`X.Y.Z` → `X+1.0.0`)
- Solo `### Sicurezza` → **PATCH** (salvo l'utente chieda diversamente)

Nel dubbio, preferisci PATCH. Chiedi conferma all'utente sulla classificazione.

### B3.2 File di versione da aggiornare
Identifica tutti i file che contengono la versione applicativa. Esempi comuni:

- **Node.js/JS/TS**: `package.json` (campo `"version"`)
- **Python**: `pyproject.toml` (`[project] version`), oppure costante in `__init__.py` o `main.py`
- **Rust**: `Cargo.toml` (`[package] version`)
- **Go**: spesso un `version.go` con costante esportata
- **Eventuali file frontend duplicati**: `src/version.ts`, `src/constants.ts`, ecc.

Verifica con `Test-Path` (PowerShell) o `[ -f path ]` (Bash) prima di toccarli.

**Obbligatorio se esiste**: un banner tipo `**Versione corrente:** vX.Y.Z` in cima al `README.md`. Cercalo (`grep -n "Versione corrente\|Current version" README.md`) e aggiornalo nello stesso commit di release. È il primo dato che legge chi apre il repo, e se resta fuori dalla routine invecchia in silenzio: su un repo reale era fermo 30 release indietro.

### B3.3 Chiudi `[Unreleased]` nel CHANGELOG
Aggiungi sotto `## [Unreleased]` (mantenendo `[Unreleased]` come header vuoto in cima) una nuova sezione `## [X.Y.Z] - YYYY-MM-DD` con tutte le voci precedentemente accumulate. Data odierna assoluta (`Get-Date -Format yyyy-MM-dd` su PowerShell, `date +%Y-%m-%d` su Bash).

### B3.4 Build frontend (se versione iniettata a build-time)
Se la versione è iniettata in fase di build (es. Vite legge `package.json`, oppure `version.ts` viene importato dal bundle), esegui il build. Aspetta esito OK; se fallisce, fermati e riporta l'errore.

### B3.5 Commit "release vX.Y.Z" (diretto su master, no PR)
`git add` esplicito sui soli file toccati nel bump:

```bash
git add <lista-file-versione> CHANGELOG.md
```

Includi tutti i file di versione effettivamente modificati. Se anche `README.md` è stato toccato per la versione corrente, includilo.

Commit (coerente con storico tipico di release commit diretti su master):

```bash
git commit -m "$(cat <<'EOF'
release vX.Y.Z

<una riga sintetica del rilascio>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### B3.6 Tag annotato
```bash
git tag -a vX.Y.Z -m "vX.Y.Z - <riga sintetica>"
```

Verifica: `git tag --sort=-v:refname | head -1` mostra il tag appena creato.

## B4. Push del rilascio su GitHub

### B4.1 Push master + tag
```bash
git push origin master --follow-tags
```

`--follow-tags` pusha solo i tag annotati raggiungibili dai commit appena pushati.

Se fallisce per non-fast-forward: **NON forzare**. `git fetch origin master`, verifica perché master remoto è ahead (probabilmente un'altra sessione ha mergiato in parallelo), risolvi, riprova.

### B4.2 Messaggio finale all'utente
Mostra esplicitamente:

```
Release vX.Y.Z pubblicata su GitHub.

Per applicare in produzione (azione manuale lato server):
  <comando specifico del progetto, es. ssh user@host && cd /opt/<app> && bash update.sh>

Lo script di update esegue tipicamente: git pull + build + restart + migrazioni.
Verifica visualmente che l'app risponda dopo l'update.
```

**Non eseguire ssh / deploy da Claude**. L'utente sceglie quando applicare (finestra di manutenzione, fuori orario, ecc.).

## Rollback (procedura manuale lato server)

In caso di failure post-update che richieda rollback rapido, indica all'utente:

```bash
ssh user@<host>
cd /opt/<app>
git checkout vX.Y.Z-1   # tag precedente
# ricostruisci/riavvia secondo il tuo stack
# se migration ha rotto schema:
# alembic downgrade -1   (o equivalente del tuo ORM)
```

Le voci del CHANGELOG vanno revertite a parte (manualmente o con nuovo commit `docs(changelog): revert ...`).

## Caveat e troubleshooting

- **Build in produzione fallisce per memoria insufficiente**: build locale + push immagine pre-built.
- **Migrazione fallisce in produzione**: leggi l'errore. Se `Multiple head revisions`, è collisione revision id (vedi A3 della skill principale).
- **Tag creato ma push fallito**: il tag locale resta. Non cancellarlo senza richiesta esplicita. Riprova `git push --follow-tags` dopo aver risolto.
