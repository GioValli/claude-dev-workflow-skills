# Skill workflow-modifiche — Dettaglio cleanup post-push (B5)

Questo file è caricato on-demand quando, dopo il push (A7) o il deploy (B4), l'utente segnala chiusura sessione ("ok a posto", "abbiamo finito", "grazie alla prossima", ecc.). Non si fa cleanup a metà sessione.

Esegui tutti i comandi **dal main repo** (`<REPO_ROOT>`), non dal worktree corrente (verrebbe rimosso durante il processo). Usa `git -C <main-repo>` con path assoluti.

## B5.1 Allinea `master` locale a `origin/master`

```bash
git -C <REPO_ROOT> fetch origin --prune
git -C <REPO_ROOT> merge --ff-only origin/master   # se sei già su master nel main repo
# altrimenti: git -C <REPO_ROOT> checkout master && merge --ff-only origin/master
```

Se il FF fallisce per **untracked files che collidono** con file in arrivo da `origin/master`:

- Confronta: `git -C <REPO_ROOT> show origin/master:<path> | diff - <full-disk-path>`
- Se **identico** → cancella la copia untracked (il merge la ricrea)
- Se **vuoto/irrilevante** → cancella
- Se **differisce con lavoro non committato** → rinomina con suffisso `.local-backup`, completa il FF, **segnalalo nel report finale**

## B5.2 Stop container Docker locali (preferenza utente)

Se durante la sessione sono stati avviati container Docker per smoke test e l'utente non sta più testando manualmente:

```bash
docker compose -f <REPO_ROOT>/docker-compose.yml down
```

Se Docker locale non è mai stato avviato in sessione, salta. Mai toccare la produzione.

## B5.3 Rimuovi il worktree corrente

```bash
git -C <REPO_ROOT> worktree remove --force <path-worktree-corrente>
git -C <REPO_ROOT> branch -d <branch-corrente>   # safe-delete
```

`branch -d` rifiuta il branch se non mergiato in master (protezione anti-perdita lavoro).

**Caveat Windows**: capita che `worktree remove` rimuova solo i metadata git ma lasci la directory fisica (file lockati da IDE, Docker desktop, indexer Windows). I metadata sono comunque puliti. Segnalalo nel report: "Directory `<path>` da rimuovere a mano dopo aver chiuso IDE e shell."

**Caveat cwd**: NON rimuovere il worktree corrente mentre la shell di Claude è dentro a quella cartella. Lavora con path assoluti e tieni la cwd fuori.

## B5.4 Audit worktree e branch stantii

```bash
git -C <REPO_ROOT> worktree list
git -C <REPO_ROOT> branch -vv
```

Per ogni worktree extra:

```bash
git -C <wt-path> rev-list --count origin/master..HEAD   # commit oltre master
git -C <wt-path> merge-base --is-ancestor HEAD origin/master   # rc=0 sì, rc=1 no
git -C <wt-path> status --short   # lavoro non committato
```

Classificazione:

- **ahead=0 + ancestor=yes + status pulito** → candidato a rimozione (procedi come in B5.3, preserva eventuali `docs/`/spec/plan locali con `Copy-Item` prima)
- **ahead>0** → **NON rimuovere**. Segnala: N commit ahead, ultimo titolo
- **status sporco con modifiche reali** → **NON rimuovere**. Segnala

Per branch locali senza worktree: se ancestor di `origin/master` → `git branch -d`. Non toccare branch `feature/*`, `feat/*` — sono dell'utente.

Concludi:

```bash
git -C <REPO_ROOT> worktree prune
```

Su Windows alcuni prune falliscono con "Permission denied" per file lock: tollerabile, segnala.

## B5.5 Report finale obbligatorio

Nell'ultimo turno della sessione **includi sempre** una sezione cleanup, anche se non c'è nulla da pulire:

```
Cleanup post-push:
- Master locale allineato a origin/master (era behind di N commit)
- Worktree corrente <path> rimosso, branch <name> eliminato
- Worktree stantii rimossi: <lista>
- Worktree con lavoro non mergiato (NON rimossi): <lista con N commit ahead, ultimo: <titolo>>
- File preservati come backup: <lista>.local-backup
- Da rimuovere a mano (file lock Windows): <lista>
- Docker locale: <fermato / non avviato>
```

Senza questo report l'utente non sa se il cleanup è successo.
