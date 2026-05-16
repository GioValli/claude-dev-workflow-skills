---
name: merge-pr
description: Chiude una Pull Request in una singola operazione: pre-merge check (mergeable, CI, review, branch up-to-date), merge commit con gh pr merge --delete-branch, cleanup post-merge (master locale allineato + worktree/branch eliminati), e proposta Fase B (bump versione + tag + push master --follow-tags). Default merge commit (no squash/rebase) per coerenza con storico PR. Triggera con "merge la PR", "chiudi la PR #N", "fai il merge", "mergiala", "completa la PR".
---

# Skill merge-pr

> **Convenzione shell** — I comandi `gh`, `git`, `docker compose` funzionano in entrambe le shell (PowerShell e Bash). I comandi con pipe Unix (`$(...)`, `|`, `xargs`) vanno eseguiti con la Bash tool, non in PowerShell.

> **Placeholder** — `<REPO_ROOT>` è il path al main repo (es. `C:/Code/<repo>` su Windows). `<GITHUB_OWNER>/<GITHUB_REPO>` è il repo remoto (es. `<owner>/<repo>`).

Chiude una Pull Request in una singola operazione: dal check pre-merge fino al tag della release su GitHub, fermandosi prima dell'azione di deploy sul server (che resta manuale o gestita da pipeline esterna).

## M0. Identificazione PR

Trigger: l'utente dice "merge la PR", "chiudi la PR #N", "fai il merge", "mergiala".

Identifica il PR number:

1. Se l'utente ha specificato un numero (es. "merge la #9") → usa quello.
2. Altrimenti auto-detect dal branch corrente:
   ```bash
   gh pr list --repo <GITHUB_OWNER>/<GITHUB_REPO> --head $(git -C <REPO_ROOT> branch --show-current) --json number --jq '.[0].number'
   ```
3. Se non c'è PR open per il branch corrente, **fermati e segnala all'utente**.

## M1. Pre-merge check

```bash
gh pr view <num> --repo <GITHUB_OWNER>/<GITHUB_REPO> --json number,state,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,isDraft,headRefName,baseRefName,title
```

Distinzione semantica importante (GitHub GraphQL API):

- `mergeable` ∈ {`MERGEABLE`, `CONFLICTING`, `UNKNOWN`} — solo presenza/assenza di conflitti
- `mergeStateStatus` ∈ {`CLEAN`, `BEHIND`, `BLOCKED`, `DIRTY`, `HAS_HOOKS`, `UNKNOWN`, `UNSTABLE`} — stato complessivo del merge

Verifica:

- `state == "OPEN"`. Se `CLOSED`/`MERGED`, fermati e segnala.
- `isDraft == false`. Se draft, chiedi all'utente se vuole prima `gh pr ready <num>`.
- `mergeable != "CONFLICTING"`. Se conflicting, segnala con istruzioni manuali (checkout branch + merge origin/master + risoluzione conflitti + push) e fermati.
- `statusCheckRollup`: se contiene entry con `conclusion == "FAILURE"` → segnala e fermati. Se contiene `status == "IN_PROGRESS"` → chiedi all'utente se vuole attendere o forzare; **no polling**. Se `[]` (nessun check eseguito, può capitare se la PR non triggera workflow) → segnala come anomalia ma non bloccare.
- `reviewDecision`: ok se vuoto (no policy) o `APPROVED`. Se `CHANGES_REQUESTED`, segnala e fermati.
- Se `mergeStateStatus == "BEHIND"`: branch dietro a master. Proponi `git -C <REPO_ROOT> fetch && git checkout <branch> && git pull --rebase origin master && git push --force-with-lease`, poi ri-esegui M1.
- Se `mergeStateStatus == "BLOCKED"`: branch protection o check obbligatorio non passato. Mostra all'utente i check rossi e fermati.

Mostra all'utente sintesi:

```
PR #N "<title>"
- State: OPEN
- Mergeable: <stato>
- Review: <stato o "no policy">
- CI: <conteggio o "no checks">
Procedo al merge? (sì/no)
```

Su `no`, fermati. Su `sì`, M2.

## M2. Esegui merge

Strategia merge commit di default:

```bash
gh pr merge <num> --repo <GITHUB_OWNER>/<GITHUB_REPO> --merge --delete-branch
```

`--delete-branch` cancella branch remoto + locale. Funziona anche se il repo ha `deleteBranchOnMerge: false`.

Strategie alternative (usa solo su richiesta esplicita dell'utente):
- `--squash` — squash di tutti i commit della PR in uno solo (perde la granularità intra-PR)
- `--rebase` — rebase dei commit della PR su master (lineare, perde il merge commit)

**Caveat: merge di PR di altri contributor** — `gh pr merge --merge` funziona se hai permessi write sul repo, anche se non sei l'autore della PR.

Verifica esito:

```bash
gh pr view <num> --repo <GITHUB_OWNER>/<GITHUB_REPO> --json state,mergeCommit
```

Atteso: `state == "MERGED"`, `mergeCommit.oid` valorizzato. Se diverso, mostra l'errore esatto di `gh pr merge` e fermati.

## M3. Cleanup post-merge

Leggi `cleanup.md` della skill `workflow-modifiche` con la tool Read, e applica i 5 sotto-step:

1. **B5.1 Allinea master locale**: `git -C <REPO_ROOT> fetch origin --prune && git -C <REPO_ROOT> merge --ff-only origin/master`
2. **B5.2 Stop container Docker** (se avviati in sessione)
3. **B5.3 Rimuovi worktree corrente** (solo se la sessione si chiude qui)
4. **B5.4 Audit worktree stantii** (no rimozione se ahead>0 o dirty)
5. **B5.5 Report finale obbligatorio**

Il report include anche:

```
Merge PR #N: COMPLETATO
- Commit di merge: <SHA>
- Branch <name> cancellato (remoto + locale)
- Master locale allineato a origin/master
```

## M4. Proposta Fase B (deploy)

Verifica commit accumulati oltre l'ultimo tag (prospettiva `origin/master`, non HEAD):

```bash
git -C <REPO_ROOT> fetch origin master --tags
LATEST_TAG=$(git -C <REPO_ROOT> describe --tags --abbrev=0 origin/master)
git -C <REPO_ROOT> rev-list ${LATEST_TAG}..origin/master --count
```

Se ritorna `0` → riporta "Nessun commit oltre l'ultimo tag, niente da rilasciare" e fine.

Se `≥1`:

```bash
git -C <REPO_ROOT> log ${LATEST_TAG}..origin/master --oneline   # commit accumulati
```

Mostra all'utente:

```
Versione attualmente taggata: vX.Y.Z
Commit accumulati oltre il tag: N
Ultimo titolo: <titolo>
Voci [Unreleased] nel CHANGELOG: <conteggio + categorie>
Bump suggerito: PATCH/MINOR/MAJOR

Vuoi rilasciare? (sì/no)
```

Su `no` → fine. Le voci restano in `[Unreleased]`.

Su `sì` → **leggi `deploy.md` della skill `workflow-modifiche` con la tool Read** e applica B3 + B4 da lì. Non duplicare i passi qui: `deploy.md` è single source of truth per la procedura di bump + tag + push, incluso edge case `[Unreleased]` vuoto.

**Non eseguire deploy/ssh da Claude**. L'azione di applicare in produzione resta manuale dell'admin IT o gestita da pipeline CI/CD.

## Errori comuni e gestione

| Errore | Causa | Azione |
|---|---|---|
| `gh: not authenticated` | Token gh scaduto | Segnala, suggerisci `gh auth login`, fermati |
| `mergeable: CONFLICTING` | Conflitti su master | Mostra istruzioni manuali, fermati |
| `--delete-branch` fallisce | Branch ha PR aperte altrove | Mostra errore `gh`, lascia branch in vita |
| `git merge --ff-only` fallisce | Untracked files che collidono | Procedi come `cleanup.md` B5.1 (diff + `.local-backup`) |
| Push tag fallisce | Tag già esistente / non-fast-forward | Mostra errore, suggerisci `git fetch + rebase`, NO `--force` su master |

## Out of scope

- Polling/wait su CI in corso
- Risoluzione automatica conflitti
- Rollback automatico
- Notifiche esterne (Slack/email)
- Deploy sul server (azione manuale dell'admin IT)
- Bump versione via PR (sempre diretto su master)

## Perché questa skill

- Chiude in 1 operazione un flusso che oggi richiede GitHub UI + Claude + Claude (3 contesti)
- Mantiene il controllo critico: ogni step distruttivo (merge, bump) chiede conferma esplicita
- Allinea automaticamente master locale a origin (no `behind` accumulato)
- Disaccoppia "release pubblicata su GitHub" (Claude) da "applicazione in produzione" (admin IT manuale)
