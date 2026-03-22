# Git — wersjonowanie kodu DailySessionLogger_v2

**Zakres:** lokalne repozytorium obejmuje **cały projekt** w folderze EA — w pierwszej kolejności **`DailySessionLogger_v2.mq5`**, potem pozostałe `.mq5` / dokumentację / skrypty pomocnicze w `scripts\`.  
**Nie chodzi wyłącznie** o skrypty reconcile w MT5; one są w `MQL5\Scripts` (często przez junctiony — patrz `docs/SCRIPTS_JUNCTIONS.md`). **Powód** na Git to **ochrona wersji EA** przed większą zmianą.

**Ochrona „wersja przed zmianą”:** przed rozpoczęciem nowej zmiany tworzysz **osobny branch** (lub tag) z działającym stanem, żeby w razie regresji móc wrócić.

**Numer wersji (CHANGELOG):** zobacz `GIT/VERSION.md` oraz tabela w `docs/CHANGE_LOG.md`.

**Pełny tutorial local + GitHub (pierwszy raz i codziennie):** → **`docs/GITHUB_SETUP_STEP_BY_STEP.md`**

---

## Typowy przepływ (branch przed zmianą)

```powershell
# Jesteś na gałęzi main (lub master), wszystko zcommitowane i działa.
git checkout -b backup/2026-03-22-pre-summary-guard
git push -u origin backup/2026-03-22-pre-summary-guard   # opcjonalnie, jeśli masz remote

# Wróć na main i rób zmiany na osobnej gałęzi roboczej:
git checkout main
git checkout -b feature/summary-append-validation
# ... edycje DailySessionLogger_v2.mq5, kompilacja, test ...
git add DailySessionLogger_v2.mq5
git commit -m "fix(EA): walidacja 14 kolumn DailySessionSummary + flush global"
```

Alternatywa: **`git tag v4.1.0-baseline`** na commicie „ostatni dobry’’ przed zmianą.

### Co wpisywać przy commicie (Cursor)

- Krótki opis w **message** (np. `fix:`, `feat:`, `chore:`).
- Przy większej zmianie: **jeden wiersz w `docs/CHANGE_LOG.md`** + ewentualnie podbicie **`GIT/VERSION.md`**.

---

## Git lokalnie (Cursor + opcjonalnie MetaEditor)

MetaEditor **nie musi** inicjować repo — wystarczy **Git w systemie** + inicjacja w katalogu projektu EA.

### 1. Instalacja Git (raz)

- [Git for Windows](https://git-scm.com/download/win)

### 2. Inicjacja repozytorium w katalogu projektu

```powershell
cd "C:\Users\<Ty>\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
git init
git add .
git status
git commit -m "chore: initial commit DailySessionLogger_v2"
```

### 3. Cursor

Po `git init` widzisz zmiany w **Source Control**. **Przed większą edycją** `DailySessionLogger_v2.mq5`: branch lub tag „baseline’’, potem commit na gałęzi roboczej.

```powershell
git tag -a v4.1.1 -m "EA: PENDING_WRITE safeguards + summary row validation"
```

### 4. MetaEditor (klonowanie vs lokalny start)

Menu **Git** w MetaEditorze obejmuje m.in. **klonowanie** zdalnego repo. **Nie jest to wymagane:** wystarczy **`git init`** w folderze projektu (PowerShell / Cursor).

**Clone z GitHuba:** opcjonalny backup / drugi komputer — najpierw `git remote add` + `push`, potem clone na innej maszynie. **Nie zastępuje** kopii CSV w `Common\Files`.

### 5. Zdalne repo (opcjonalnie)

```powershell
git remote add origin https://github.com/<user>/<repo>.git
git branch -M main
git push -u origin main
```

---

## GitHub + Clone w MetaEditor — jak to się układa z Cursorem

**Kolejność typowa (masz już projekt w `Experts\Advisors\DailySessionLogger_v2`):**

1. W tym folderze: `git init` (jeśli jeszcze nie), commity lokalnie.
2. Na GitHubie: nowe **puste** repo.
3. `git remote add origin ...` + **`git push -u origin main`** — wtedy **cały** obecny kod jest na GitHubie.

**Clone z MetaEditora** tworzy **drugi** katalog na dysku z kopią repo — **nie musisz** z tego korzystać na tym samym PC, jeśli już pracujesz w folderze EA. Clone ma sens: drugi komputer, czysty katalog, albo gdy wolisz MT5 tylko przy „wydaniu’’.

**Cursor a GitHub:**

- Cursor edytuje **lokalne pliki** i używa **lokalnego** `git` (commit/branch).
- **Push/pull** do GitHuba działają tak samo jak w terminalu: po skonfigurowaniu **SSH** albo **HTTPS + Personal Access Token** (PAT) / Git Credential Manager. Cursor **nie traci** możliwości poprawiania kodu — tokeny to kwestia **Git na Windowsie**, nie „wyłączenia’’ Cursora.
- MetaEditor i Cursor mogą wskazywać **ten sam folder** z `.git` — wtedy oba widzą tę samą historię; nadal **jeden** `push` na remote (z Cursora lub z linii poleceń).

**Lokalny `git init` + branch/tag** **nadal ma sens** nawet przy GitHubie: to podstawowy workflow (szybkie odgałęzienia, tag baseline). GitHub to **backup i synchronizacja**, nie zamiennik.

**Cursor „sam’’ nie założy Ci konta GitHub** — musisz konto i repo utworzyć w przeglądarce. Możesz poprosić AI w Cursorze o **gotowe komendy** `git remote` / `push` po podaniu URL repo (bez hasła w czacie — PAT wpisujesz lokalnie przy pierwszym pushu).
