---
name: workflow-modifiche
description: Applica un workflow in 2 fasi per chiudere ogni modifica al codice. Fase A (per modifica autocontenuta) pre-flight check, build, audit migrazioni database, demo e workflow d'uso su richiesta per le modifiche visibili, CHANGELOG, pagina del manuale d'uso (o audit README se il progetto non ha un manuale), commit Conventional, push branch/PR di default o FF diretto solo per piccoli fix. Fase B (post-merge master) rileva commit accumulati oltre tag, propone deploy, bump versione su conferma, tag, push master --follow-tags, cleanup worktree. Verifica sempre sessioni parallele (worktree multipli) e collisioni di revision id nelle migrazioni. Usa questa skill ogni volta che modifichi codice, anche per cambi minimi, anche su branch lunghi. Non saltare i passi.
---

# Workflow modifiche codice

> **Convenzione shell** — Su Windows + PowerShell, i comandi POSIX (`grep`, `find`, `xargs`, `uniq`, `sort`) non funzionano nativamente: vanno eseguiti con la Bash tool (git bash è disponibile via WSL/Git for Windows). I comandi `Test-Path`, `Get-Date`, `Copy-Item` sono PowerShell-only. I comandi `git`/`gh`/`docker compose`/`npm` funzionano in entrambe. Su Linux/macOS la distinzione non si pone.

> **Placeholder** — Questa skill usa `<REPO_ROOT>` per indicare il path al main repo (tipicamente `C:/Code/<repo>` su Windows o `~/code/<repo>` su Unix), `<GITHUB_OWNER>/<GITHUB_REPO>` per il repo remoto, `<MIGRATIONS_DIR>` per la cartella delle migrazioni del tuo ORM (es. `backend/alembic/versions` con Alembic, `db/migrate` con Rails, `prisma/migrations` con Prisma), `<MANUAL_DIR>` per la cartella del manuale d'uso del progetto (pagine Markdown + sottocartella `img/`, es. `docs/manuale` o `frontend/public/manuale-md`; il percorso reale è indicato nel `CLAUDE.md`/`AGENTS.md` del progetto). Adatta ai path del tuo progetto.

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

### A3bis. Demo e workflow d'uso (su richiesta, solo per modifiche visibili)

Dopo build/test (e migrazioni applicate) e **prima** di CHANGELOG, commit e PR.

1. **Classifica la modifica.**
   - **Visibile** all'utente: pagine o schermate nuove/cambiate, flussi d'uso, permessi/ruoli, notifiche, stampe/export, messaggi mostrati all'utente.
   - **Interna**: calcoli senza effetto sull'interfaccia, test, refactor, dipendenze, sola documentazione, CI.
2. **Modifica interna** → nessuna domanda. Dichiaralo nel riepilogo: *"Demo: non necessaria (modifica interna)."* Passa ad A4.
3. **Modifica visibile** → **chiedi** all'utente, con una domanda esplicita, se vuole:
   - una **demo**: app avviata in locale su **dati fittizi**, con schermate reali dei passaggi toccati;
   - il **workflow d'uso** passo passo (chi fa cosa, da quale pagina, con quale risultato).

   **Mai dare per scontato il sì**, nemmeno se in passato ha sempre accettato: si chiede ogni volta.
4. **Con il sì:**
   - avvia l'app in locale (comandi dal `CLAUDE.md`/`AGENTS.md`), popola dati fittizi (seed/fixture del progetto o dati creati per l'occasione), **mai dati di produzione**;
   - mostra le schermate dei passaggi e scrivi il workflow passo passo;
   - **attendi l'approvazione esplicita**. Se l'utente chiede correzioni → torna ad A1, poi ripeti A2-A3bis.
   - Conserva le schermate approvate: diventano le immagini della pagina del manuale in A5.
5. **Con il no:** prendine nota nel riepilogo (*"Demo: rifiutata dall'utente"*) e prosegui.

**La PR (A7) si apre solo dopo l'approvazione della demo**, quando è stata richiesta.

### A4. Aggiorna `CHANGELOG.md` (solo `[Unreleased]`)

Sotto `## [Unreleased]`, aggiungi una voce sintetica. Raggruppa per categoria (formato [Keep a Changelog](https://keepachangelog.com/) tradotto in italiano):

- `### Aggiunte` — nuove feature/file/pulsanti/comandi (`Added`)
- `### Modifiche` — comportamento di qualcosa che già esisteva (`Changed`)
- `### Fix` — bug risolti (`Fixed`)
- `### Rimozioni` — cose tolte (`Removed`)
- `### Sicurezza` — patch di sicurezza (`Security`)
- `### Documentazione` — aggiornamenti manuale d'uso/README/CHANGELOG/docs (**categoria custom**, non standard Keep a Changelog — utile se manuale, README e CHANGELOG sono tenuti sincronizzati)

Categoria standard Keep a Changelog non sempre usata: `Deprecated` (rimuovi direttamente in versione MAJOR se hai una policy di rilascio aggressiva).

Ogni voce è 1-2 righe: **cosa è cambiato e perché**, non il come.

**Non fare**: chiudere `[Unreleased]` con una nuova versione, toccare i file di versione (`package.json`, ecc.), creare tag. Tutto questo è Fase B.

### A5. Manuale d'uso (e audit README per le voci operative)

Il **manuale d'uso** spiega come si usano le funzioni; il **README** resta per presentazione, installazione, deploy e configurazione. Un README che descrive ogni funzione diventa infinito e resta sempre indietro: le funzioni vanno nel manuale, una pagina per funzione o area, con immagini.

**Dove sta il manuale.** Il percorso è specifico del progetto: leggilo dal `CLAUDE.md`/`AGENTS.md` (qui `<MANUAL_DIR>`). Se il progetto **non ha un manuale** (nessuna indicazione e nessuna cartella evidente), salta il punto 1 e applica l'audit README del punto 2 anche alle voci user-visible (comportamento classico: sezioni Funzionalità, Permessi, Notifiche del README).

Confronta le voci appena aggiunte (e tutte quelle accumulate sotto `[Unreleased]`) con manuale e README:

1. **Modifica visibile → pagina del manuale.**
   - Aggiorna (o crea) la pagina di `<MANUAL_DIR>` che descrive la funzione: a cosa serve, chi può usarla, il workflow passo passo, eventuali avvisi. Il workflow approvato in A3bis è la base del testo.
   - Immagini in `<MANUAL_DIR>/img/`: le schermate della demo, **solo da dati fittizi, mai da produzione** (niente nomi, email, importi o documenti reali), **compresse** (PNG ottimizzato o WebP/JPEG, larghezza ragionevole, idealmente < 200 KB l'una), con nomi parlanti (`<funzione>-<passo>.png`). Senza demo, aggiorna almeno il testo e segnala nel riepilogo che mancano le immagini.
   - Se il progetto ha un indice delle pagine (sommario, menu, file di indice), aggiungi la voce.
   - Aggiungi una voce sotto `### Documentazione` di `[Unreleased]` ("Manuale: pagina X — Y") e includi pagina e immagini nello **stesso commit/PR** della modifica.
   - Non duplicare nel README la descrizione della funzione: al massimo un rimando al manuale.
2. **Voce operativa → audit README.** Se il README non è in contesto, leggilo con la tool Read. Classifica:

   | Tipo voce | Dove va | Sezione tipica |
   |---|---|---|
   | Nuovo modulo / feature user-visible | Manuale (README solo se il progetto non ha manuale) | pagina della funzione |
   | Nuovo ruolo / cambio permessi | Manuale (README solo se il progetto non ha manuale) | pagina della funzione / Permessi |
   | Nuovo tipo notifica / nuovo canale | Manuale (README solo se il progetto non ha manuale) | pagina Notifiche |
   | Nuova env var / cambio deploy / nuovo volume / nuovo job scheduler | README | Deploy/Configurazione |
   | Fix bug / refactor / migration interna / dipendenze senza impatto utente | nessuno | — |

   Se c'è almeno una voce operativa → aggiorna le sezioni del README, aggiungi una voce sotto `### Documentazione` ("README aggiornato: sezione X — Y") e includi `README.md` nello **stesso commit** della feature.
3. Se tutte le voci sono interne → dichiara esplicitamente in chat: *"Manuale e README: nessun aggiornamento necessario."*

Caso edge: se la modifica corrente è "documentazione pura" (typo in CHANGELOG/README/manuale), salta questo passo.

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
- [ ] Demo: approvata / non richiesta / non necessaria (modifica interna)
- [ ] Manuale d'uso: pagina aggiornata / non necessario
- [ ] Audit README (voci operative): fatto / non necessario

EOF
)"
```

Se in A3bis l'utente ha chiesto la demo, la PR si apre **solo dopo** la sua approvazione esplicita.

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
- **Demo prima della PR**: per le modifiche visibili l'utente vede schermate reali su dati fittizi e approva prima che la PR esista.
- **Manuale d'uso sempre allineato**: ogni funzione visibile aggiorna la sua pagina, con immagini, nella stessa PR; il README resta corto (presentazione, installazione, deploy, configurazione).
- **Sessioni parallele tracciate**: worktree multipli senza collisioni silenti su CHANGELOG/migrazioni.
- **Bump al deploy reale**: niente versioni fantasma, i tag corrispondono a release effettive.
