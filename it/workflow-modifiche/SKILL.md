---
name: workflow-modifiche
description: Applica un workflow in 2 fasi per chiudere ogni modifica al codice. Fase A (per modifica autocontenuta) pre-flight check, build, audit migrazioni database, CHANGELOG, audit README, commit Conventional, push branch/PR di default o FF diretto solo per piccoli fix. Fase B (post-merge master) rileva commit accumulati oltre tag, propone deploy, bump versione su conferma, tag, push master --follow-tags, cleanup worktree. Verifica sempre sessioni parallele (worktree multipli) e collisioni di revision id nelle migrazioni. Usa questa skill ogni volta che modifichi codice, anche per cambi minimi, anche su branch lunghi. Non saltare i passi.
---

# Workflow modifiche codice

> **Convenzione shell** — Su Windows + PowerShell, i comandi POSIX (`grep`, `find`, `xargs`, `uniq`, `sort`) non funzionano nativamente: vanno eseguiti con la Bash tool (git bash è disponibile via WSL/Git for Windows). I comandi `Test-Path`, `Get-Date`, `Copy-Item` sono PowerShell-only. I comandi `git`/`gh`/`docker compose`/`npm` funzionano in entrambe. Su Linux/macOS la distinzione non si pone.

> **Placeholder** — Questa skill usa `<REPO_ROOT>` per indicare il path al main repo (tipicamente `C:/Code/<repo>` su Windows o `~/code/<repo>` su Unix), `<GITHUB_OWNER>/<GITHUB_REPO>` per il repo remoto, `<MIGRATIONS_DIR>` per la cartella delle migrazioni del tuo ORM (es. `backend/alembic/versions` con Alembic, `db/migrate` con Rails, `prisma/migrations` con Prisma). Adatta ai path del tuo progetto.

Questa skill codifica l'abitudine di chiudere ogni modifica di codice con un mini-ciclo controllato, e di disaccoppiare la modifica feature dal momento del rilascio. Il workflow è in **due fasi**:

- **Fase A** — per ogni modifica autocontenuta (feature/fix/refactor/docs). Si esegue **per intero** prima di passare al prossimo task, anche se la modifica sembra piccola.
- **Fase B** — quando `master`/`main` è cambiato (post-merge PR o post-FF diretto) e ci sono commit oltre il tag più recente. Si esegue **solo su conferma esplicita dell'utente** per proporre/eseguire un rilascio.

Regola chiave: **il bump versione NON è per-commit, non è per-PR, non è per-fine-sessione**. Si fa solo in Fase B, quando l'utente decide di rilasciare. Le voci si accumulano sotto `## [Unreleased]` del CHANGELOG da una o più PR di sessioni diverse, e vengono chiuse in `## [X.Y.Z] - YYYY-MM-DD` solo al rilascio.

## Fase A — Per ogni modifica autocontenuta

### A0. Pre-flight check

Prima di toccare file:

1. `git status` → working tree pulito (no rebase/merge/cherry-pick in corso). Se c'è un'operazione in pausa, **fermati e segnala all'utente**.
2. Branch corrente: deve essere `claude/*` o `feature/*` o equivalente. **Non lavorare direttamente su `master`/`main`**.
3. `git worktree list` → registra altri worktree attivi.
4. Per ogni altro worktree: `git -C <path> status --short` + `git -C <path> diff origin/master --name-only`. Se altri worktree hanno modificato `CHANGELOG.md`, file in `<MIGRATIONS_DIR>`, file con la versione applicativa (`package.json`, `pyproject.toml`, `Cargo.toml`, ecc.) o `README.md` → **segnala all'utente il rischio di conflitto** (non bloccare).

### A1. Applica la modifica

Edita i file. Se la modifica spazia su più file, pensala come unico cambio logico coerente: tutti i file necessari vanno nello stesso commit finale.

### A2. Verifica build/test

Standard generici (adatta al tuo stack):

- Frontend toccato → comando di build (`npm run build`, `yarn build`, `pnpm build`, ecc.). Obbligatorio. Fallimento = blocco.
- Backend toccato → syntax check + type check (`python -m compileall <dir>`, `mypy`, `tsc --noEmit`, ecc.). Obbligatorio. Fallimento = blocco.
- Test mirati: solo se l'utente li richiede o `CLAUDE.md`/`AGENTS.md` li menziona come obbligatori per ogni modifica.

Il `CLAUDE.md`/`AGENTS.md` del progetto ha precedenza sui comandi qui prescritti.

### A3. Verifica migrazioni database (se toccato `<MIGRATIONS_DIR>`)

Solo se la modifica ha aggiunto/modificato file in `<MIGRATIONS_DIR>`:

1. Verifica che ci sia **una sola head**:
   - Alembic: `alembic heads` → atteso **una sola riga** del tipo `<rev_id> (head)`
   - Rails: `rails db:migrate:status` → ultima migration applicata
   - Prisma: nessun comando equivalente — verifica `prisma migrate status`
2. Verifica revision id non duplicato (esempio per Alembic, esegui con la Bash tool):
   ```bash
   grep -h "^revision = " <MIGRATIONS_DIR>/*.py | sort | uniq -d
   ```
   Atteso: **nessun output**. Se output non vuoto, ogni riga stampata è un `revision = "..."` duplicato in più file.

   Per scoprire QUALI file collidono:
   ```bash
   grep -H "^revision = " <MIGRATIONS_DIR>/*.py | sort -t'"' -k2
   ```
   e individua a occhio le righe con stesso `revision = "..."`.
3. Check cross-worktree: per ogni altro worktree visto in A0 con migration aggiunta, verifica che la revision/id del tuo file sia diverso dai loro.
4. Chain `down_revision` lineare (Alembic): `alembic history --verbose | head -50` per verifica visiva.

**Procedura risoluzione collisione** (capita quando due sessioni parallele aggiungono migrazioni in branch diversi):

- Identifica i due file con id duplicato
- Rinomina il tuo file: `NNN_descrizione.py` → `MMM_descrizione.py` (incrementa al primo numero libero)
- Aggiorna nel file: `revision = "<nuovo_id>"` e `down_revision = "<id_della_head_corrente>"`
- Verifica con dry-run che la chain sia valida (es. `alembic upgrade head --sql`)

### A4. Aggiorna `CHANGELOG.md` (solo `[Unreleased]`)

Sotto `## [Unreleased]`, aggiungi una voce sintetica. Raggruppa per categoria (formato [Keep a Changelog](https://keepachangelog.com/) tradotto in italiano):

- `### Aggiunte` — nuove feature/file/pulsanti/comandi (`Added`)
- `### Modifiche` — comportamento di qualcosa che già esisteva (`Changed`)
- `### Fix` — bug risolti (`Fixed`)
- `### Rimozioni` — cose tolte (`Removed`)
- `### Sicurezza` — patch di sicurezza (`Security`)
- `### Documentazione` — aggiornamenti README/CHANGELOG/docs (**categoria custom**, non standard Keep a Changelog — utile se README e CHANGELOG sono manuali sincronizzati)

Categoria standard Keep a Changelog non sempre usata: `Deprecated` (rimuovi direttamente in versione MAJOR se hai una policy di rilascio aggressiva).

Ogni voce è 1-2 righe: **cosa è cambiato e perché**, non il come.

**Non fare**: chiudere `[Unreleased]` con una nuova versione, toccare i file di versione (`package.json`, ecc.), creare tag. Tutto questo è Fase B.

### A5. Audit README pre-commit

Confronta le voci appena aggiunte (e tutte quelle accumulate sotto `[Unreleased]`) con `README.md`:

1. Se il README non è in contesto, leggilo con la tool Read.
2. Per ciascuna voce classifica l'impatto:

   | Tipo voce | Impatta README? | Sezione tipica |
   |---|---|---|
   | Nuovo modulo / feature user-visible | Sì | Funzionalità |
   | Nuovo ruolo / cambio permessi | Sì | Sicurezza/Permessi |
   | Nuovo tipo notifica / nuovo canale | Sì | Notifiche |
   | Nuova env var / cambio deploy / nuovo volume / nuovo job scheduler | Sì | Deploy/Configurazione |
   | Fix bug / refactor / migration interna / dipendenze senza impatto utente | No | nessuna |

3. Se almeno una voce è user-visible/operativa → aggiorna le sezioni del README, aggiungi una voce sotto `### Documentazione` di `[Unreleased]` ("README aggiornato: sezione X — Y"), e includi `README.md` nel `git add` dello **stesso commit** della feature.
4. Se tutte le voci sono interne → dichiara esplicitamente in chat: *"Audit README: nessun aggiornamento necessario."*

Caso edge: se la modifica corrente è "documentazione pura" (typo in CHANGELOG/README), salta l'audit.

### A6. Commit git

**Convenzione Conventional Commits con scope**:

```
<tipo>(<scope>): <descrizione>

[corpo opzionale]

Co-Authored-By: Claude <noreply@anthropic.com>
```

- Tipi: `feat`, `fix`, `docs`, `refactor`, `style`, `chore`, `test`
- Scope: modulo o area (`auth`, `api`, `frontend`, `db`, ecc.)
- Descrizione: ≤72 char sulla prima riga
- Corpo: solo se serve spiegare il "perché" (riga vuota di separazione)
- Firma `Co-Authored-By` consigliata se Claude ha contribuito

Regole operative:

- `git add` esplicito sui file toccati. **Mai** `git add .` o `git add -A`.
- **Non** usare `--no-verify` per saltare hook pre-commit. Se un hook fallisce, risolvi la causa e crea un **nuovo** commit (non `--amend`).
- Multi-riga via HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
feat(scope): descrizione

Corpo esteso se serve.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### A7. Push & integrazione con master

Push del branch corrente:

```bash
git push -u origin <branch-corrente>
```

Poi decidi **PR** (default) o **FF diretto** (eccezione).

#### Default: Pull Request

```bash
gh pr create --title "<tipo>(<scope>): <descrizione>" --body "$(cat <<'EOF'
## Sommario
- <bullet 1>
- <bullet 2>

## Test
- [ ] Build frontend OK
- [ ] Syntax/type check backend OK
- [ ] (se applicabile) migrazioni applicate OK
- [ ] Audit README: fatto / non necessario

EOF
)"
```

Dopo la PR, **Fase B non parte** finché la PR non viene mergiata.

#### Eccezione: FF diretto branch:master

Consentito **solo** se TUTTI questi criteri sono rispettati:

- 1 solo commit
- Tipo `fix(...)`, `docs(...)`, `chore(...)` o `style(...)` — **mai** `feat(...)`
- Diff totale ≤200 righe
- Nessun file in `<MIGRATIONS_DIR>`
- Nessun file nei modelli ORM
- Nessun file in `.github/workflows/` (modificare la CI è la cosa che valida le PR — modificarla in FF è un rischio circolare)
- Nessuna nuova/rimossa dipendenza
- Nessun breaking change API
- Nessun cambio in file di deploy (`docker-compose*.yml`, IaC, script di update)

Anche **uno solo** violato → PR obbligatoria.

Se tutti rispettati, opzione FF:

```bash
git push origin <branch-corrente>:master --follow-tags
```

Fast-forward server-side, niente merge commit. `master` locale del main repo resta dietro (lo allinei in B5).

### Quando applicare Fase A

Concetto chiave: **modifica funzionale autocontenuta** — un cambio che ha senso compiuto la cui assenza non romperebbe niente.

| Scenario | Un commit o più? |
|---|---|
| Cambiare un campo in un form | **Uno** |
| Fix di un path sbagliato in 4 file | **Uno** (stesso fix logico) |
| Aggiungere campo: modello + salvataggio + UI | **Uno** (stessa feature) |
| Feature + refactor scollegato | **Due** commit separati |
| Fix bug A + fix bug B non correlato | **Due** commit separati |

In dubbio, preferisci più commit piccoli a uno grosso.

### Eccezioni & debito di commit

Salti A4-A6 (CHANGELOG+commit) **solo** se l'utente lo dice esplicitamente:

- **"non committare ora"** → applichi A1+A2, **registri il debito** in chat ("Debito di commit aperto: modifiche a X non committate. Da chiudere prima di fine sessione."), a fine sessione ricordi all'utente.
- **"non committare mai" / "buttalo" / "scartalo"** → eseguo `git restore .` solo sui file da me modificati. Nessun debito registrato.
- **"testiamo prima"** → applichi A1+A2, attendi conferma test OK, poi riprendi da A3.

## Fase B — Quando master cambia (post-merge / post-FF)

### B0. Trigger Fase B

Verifica che la fase sia applicabile (usa `origin/master` come prospettiva, NON HEAD — il branch corrente potrebbe non contenere il tag più recente):

```bash
git fetch origin master --tags
LATEST_TAG=$(git describe --tags --abbrev=0 origin/master)
git rev-list ${LATEST_TAG}..origin/master --count  # commit di master oltre il tag
```

Se ritorna `0` → nessun cambio da rilasciare, **non proporre deploy**.

Se ritorna `≥1` → ci sono commit accumulati. Procedi a B1.

### B1. Mostra info deploy

Presenta sinteticamente all'utente:

```
Versione attualmente deployata: vX.Y.Z (tag git)
Commit accumulati oltre il tag: N
Ultimo titolo: <titolo del commit più recente>
Voci [Unreleased] nel CHANGELOG: <conteggio + categorie>
```

Il dato sulla versione deployata si ottiene da `git describe --tags --abbrev=0 origin/master`. Se l'app espone un endpoint `/health` o `/version`, quello è la fonte primaria.

#### Edge case: `[Unreleased]` vuoto ma N commit accumulati

Capita quando i commit accumulati sono solo CI/chore senza ricaduta utente. Procedura:

1. Mostra all'utente la lista dei commit accumulati:
   ```bash
   git log ${LATEST_TAG}..origin/master --oneline
   ```
2. Chiedi: "Nessuna voce in `[Unreleased]`. Vuoi (a) saltare il rilascio, (b) generare voci CHANGELOG dai titoli dei commit, oppure (c) rilasciare comunque senza voci?"
3. Su (b): genera draft entries categorizzando dai prefissi `feat(...)/fix(...)/chore(...)`, mostrale all'utente per conferma prima di scriverle in CHANGELOG.
4. Su (c): bump PATCH d'ufficio, aggiungi una sola voce `### Modifiche` con "Aggiornamenti tecnici interni (vedi git log)".

### B2. Proponi deploy

Domanda esplicita:

> "Vuoi rilasciare con questi N commit accumulati? Categoria bump suggerita: <PATCH/MINOR/MAJOR>"

**Mai eseguire B3-B4 senza conferma esplicita dell'utente.** Anche se in passato ha detto "sì sempre" — il deploy è azione irreversibile con blast radius fuori dalla macchina locale.

Se l'utente dice no → fine, le voci restano in `[Unreleased]` per il prossimo deploy.

Se sì → leggi `deploy.md` con la tool Read e segui B3 + B4.

### B5. Cleanup post-push

Quando l'utente segnala chiusura sessione ("ok a posto", "abbiamo finito", "grazie alla prossima"), leggi `cleanup.md` con la tool Read e segui i 5 sotto-step. Il report finale è obbligatorio anche se non c'è nulla da pulire.

## Se il progetto ha `CLAUDE.md` o `AGENTS.md`

Se la root del repo contiene `CLAUDE.md` o `AGENTS.md`, leggilo **all'inizio della sessione**. Il suo contenuto **prevale** su prescrizioni generiche di questa skill (es. comandi di build, file di versione, convenzioni di scope nei commit). Questa skill è il default; il file di progetto è la verità.

## Perché questo workflow

- **Storico leggibile**: ogni commit fa una cosa chiara, `git log` racconta l'evoluzione senza archeologia.
- **Rollback chirurgici**: `git revert` rimuove un cambio senza toccare il resto.
- **CHANGELOG sempre aggiornato**: al momento del rilascio il documento è pronto.
- **README sempre allineato**: gli utenti che leggono GitHub non vedono mai un manuale obsoleto rispetto al codice.
- **Sessioni parallele tracciate**: worktree multipli senza collisioni silenti su CHANGELOG/migrazioni.
- **Bump al deploy reale**: niente versioni fantasma, i tag corrispondono a release effettive.
