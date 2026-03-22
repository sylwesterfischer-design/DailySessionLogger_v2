# Git lokalny + GitHub (remote) — krok po kroku

Folder projektu (u Ciebie):  
`...\MQL5\Experts\Advisors\DailySessionLogger_v2`

**Cursor nie instaluje Gita ani nie zakłada konta GitHub za Ciebie** — to robisz Ty w przeglądarce / instalatorze. Cursor potem edytuje **ten sam folder** i robi `commit` jak zwykle.

### Cursor a Git — czy trzeba „dać uprawnienia” Cursorowi?

**Nie ma** w systemie osobnej opcji typu *Allow Cursor to use Git*. Zintegrowany terminal Cursora uruchamia polecenia jako **Ty** (to samo konto Windows co zwykły PowerShell).

- Jeśli po instalacji Gita `git --version` działa w **PowerShellu poza Cursorem**, a w Cursorze nie — **zrestartuj Cursor** lub otwórz **nowy** terminal (odświeżenie **PATH**).
- Logowanie do GitHuba (**HTTPS**) obsługuje **Git Credential Manager** — po pierwszym `git push` / zalogowaniu token zostaje w **magazynie Windows**; agent korzysta z tego samego `git`, nie wymaga dodatkowej konfiguracji „dla AI”.

### Co to jest **MINGW64** w tytule okna **Git Bash**?

**Git Bash** to powłoka **bash** dołączona do *Git for Windows*. **MINGW64** oznacza środowisko **MinGW-w64** (Minimalist GNU for Windows, 64-bit) — warstwę, która udostępnia na Windows typowe polecenia w stylu Unixa.  
**To nie jest osobny „tryb Gita”** — to tylko inny terminal. W Cursorze zwykle używasz **PowerShell**; **MINGW64 / Git Bash** nie są wymagane, żeby agent mógł odpalać `git`.

---

## Część A — pierwszy raz (narzędzia)

### A1. Git na Windows

1. Pobierz: [git-scm.com/download/win](https://git-scm.com/download/win)
2. Uruchom instalator. Większość kroków możesz zostawić **domyślnie** (zalecane: **Git Credential Manager** — ułatwia logowanie do GitHuba).

#### A1a. Krok „Choosing the default editor used by Git”

Instalator pyta, **jakiego edytora** ma używać Git przy `git commit` **bez** `-m` (edycja komunikatu w osobnym oknie) oraz niektórych innych poleceń.

**Co wybrać (Cursor / ten projekt):**

| Opcja w instalatorze | Kiedy ma sens |
|----------------------|----------------|
| **Use Visual Studio Code as Git's default editor** | Sensowne, jeśli masz **zainstalowany VS Code** i `code` w PATH — komunikaty commitów otworzą się w VS Code. **Cursor** na liście zwykle **nie ma** (to fork VS Code). |
| **Use Notepad as Git's default editor** | **Najprostsze**, gdy commity robisz głównie z **Cursora** (Source Control / `-m "..."`) i rzadko otwierasz zewnętrzny edytor z linii poleceń. |
| **Use Notepad++ …** | Jeśli na co dzień używasz Notepad++. |
| **Use Vim …** (domyślne) | Dla osób znających Vim; **nie polecane**, jeśli Vim Ci nie pasuje. |

**Żeby commity z terminala otwierały się w Cursorze** (po instalacji Gita), w PowerShell:

```powershell
git config --global core.editor "cursor --wait"
```

**Brak jakiegokolwiek komunikatu po tej komendzie = zwykle OK** (Git przy sukcesie nic nie drukuje). Sprawdź:

```powershell
git config --global --get core.editor
```

Oczekiwany wynik: `cursor --wait`.  
Dalej upewnij się, że Windows widzi `cursor`:

```powershell
where.exe cursor
```

Jeśli `where` nic nie zwraca — w Cursorze: **Ctrl+Shift+P** → *Shell Command: Install 'cursor' command in PATH* → **nowe** okno PowerShell.

Działa, gdy polecenie **`cursor`** jest w PATH. Jeśli nadal nie — zostaw edytor z instalatora (**Notepad**) albo ustaw pełną ścieżkę do `Cursor.exe`, np. (dostosuj folder wersji):

```powershell
git config --global core.editor "'C:\Users\cewue\AppData\Local\Programs\cursor\Cursor.exe' --wait"
```

3. Dokończ instalację, **nowe** okno PowerShell i sprawdź:

```powershell
git --version
```

#### A1b. Krok „Adjusting the name of the initial branch in new repositories”

Pytanie: jak nazwać domyślną gałąź po **`git init`**?

**Zalecenie (GitHub + ta instrukcja):**

- Zaznacz **Override the default branch name for new repositories**
- W polu wpisz: **`main`**

Dzięki temu nowe repozytoria od razu mają gałąź **`main`**, jak w **§ B3** (`git branch -M main`) i jak na GitHubie.  
**Uwaga:** ustawienie **nie zmienia** już istniejących repo — tylko **nowe** `git init`.

Jeśli zostawisz **Let Git decide**, domyślnie może być **`master`** — wtedy albo zmienisz nazwę (`git branch -M main`), albo na GitHubie utworzysz repo z gałęzią `master` (mniej typowe dziś).

#### A1c. Krok „Adjusting your PATH environment”

Pytanie: skąd wywoływać Git?

**Zalecenie:** zostaw zaznaczone (**Recommended**):

**Git from the command line and also from 3rd-party software**

Dzięki temu `git` działa w **PowerShell**, **cmd** i w narzędziach takich jak **Cursor** (terminal / agent), bez ograniczenia tylko do Git Bash.

**Unikaj** trzeciej opcji (*Git and optional Unix tools from the Command Prompt*), chyba że wiesz, że nadpiszesz polecenia Windows (`find`, `sort`, …).

#### A1d. Krok „Choosing the SSH executable”

Pytanie: którego klienta SSH ma używać Git (np. przy `git clone git@github.com:...`)?

**Zalecenie (najmniej problemów w terminalu Cursora / agencie):**

**Use bundled OpenSSH**

- `ssh.exe` jest **razem z Git for Windows** — zawsze spójna wersja obok `git`, bez zgadywania, co jest w PATH.
- **Cursor** wywołuje te same polecenia co Ty w PowerShellu; **bundled** zwykle oznacza mniej „u mnie działa, w agencie nie”.

**Use external OpenSSH** — wybierz tylko wtedy, gdy **świadomie** chcesz używać **jednego** OpenSSH z Windows (Opcje → Aplikacje → OpenSSH) lub innej instalacji już w PATH i masz skonfigowany **ssh-agent** / klucze pod ten `ssh`. Dla typowej pracy z **HTTPS + Git Credential Manager** SSH i tak bywa rzadziej używane — bundled nadal jest OK.

#### A1e. Krok „Choosing the HTTPS transport backend” (TLS)

Pytanie: OpenSSL czy biblioteka Windows?

**Zalecenie (Windows + GitHub + Cursor / agent w terminalu):**

**Use the native Windows Secure Channel library** *(albo podobna nazwa: schannel / Secure Channel)*

- Lepsza integracja z **magazynem certyfikatów Windows** i często mniej problemów za **firmowym proxy / antywirusem** niż czysty OpenSSL.
- **Git Credential Manager** i **`git clone` / `git pull` przez HTTPS** działają tak samo z poziomu PowerShella w Cursorze.

**OpenSSL** — OK, jeśli wolisz klasyczny zestaw lub masz konkretny powód (np. dokumentacja zespołu).

#### A1f. Krok „Configuring line ending conversions”

Pytanie: jak traktować końce linii (CRLF vs LF)?

**Zalecenie pod Cursor + GitHub (spójne diffy, mniej „szumu” w repo):**

Często druga opcja w stylu: **Checkout as-is, commit Unix-style line endings** *(„wypuszczaj LF do repozytorium”)* — pliki w GitHubie zostają z **LF**; lokalnie edytor (Cursor) i tak zwykle radzi sobie z oboma.

**Pierwsza opcja** (*Checkout Windows-style, commit Unix-style*) — też popularna na Windows; zamienia CRLF przy checkout, do repo idzie LF. Wybierz ją, jeśli inne programy wymagają CRLF na dysku.

**Trzecia** (*Checkout as-is, commit as-is*) — tylko gdy **świadomie** nie chcesz normalizacji (rzadziej dla projektów współdzielonych).

**Jeśli masz już zaznaczoną pierwszą opcję** (*Checkout Windows-style, commit Unix-style*, **Recommended** na Windows) — **zostaw**; dla Cursora / agenta w terminalu jest **w porządku** (do repo i tak leci LF).

#### A1g. Krok „Configuring the terminal emulator” (Git Bash)

Dotyczy tylko **Git Bash**, nie **PowerShella w Cursorze**.

- **Use MinTTY** (domyślnie) — wygodne okno Bash (zmiana rozmiaru, Unicode).  
- **Use Windows' default console window** — czasem prostsze dla **interaktywnego** Pythona/node **wewnątrz Git Bash** (bez `winpty`).

**Dla Cursora:** zwykle pracujesz w **PowerShellu zintegrowanym** — ten wybór **prawie nie wpływa** na agenta. **MinTTY** możesz spokojnie zostawić.

#### A1h. Krok „Choose the default behavior of `git pull`”

**Zalecenie (bezpieczne, przewidywalne):**

**Fast-forward or merge** *(pierwsza opcja, tradycyjna)*

- Cursor/agent robi to samo, co standardowy Git — mniej niespodzianek niż domyślne **rebase** dla osób, które nie pracują codziennie z `git rebase`.

**Rebase** — OK dla zespołu, który **świadomie** chce liniową historię; wymaga znajomości rozwiązywania konfliktów przy rebase.

**Only ever fast-forward** — ścisłe; `git pull` **padnie**, gdy potrzebny byłby merge — może utrudniać agentowi „szybki pull”, jeśli gałąź rozjechana.

#### A1i. Krok „Choose a credential helper”

**Git Credential Manager** *(zalecane, zwykle domyślne)*

- Tokeny / logowanie do GitHuba trafiają do **magazynu Windows** — **`git push` / `git pull` z terminala Cursora** często działają **bez** ręcznego wpisywania hasła przy każdym poleceniu.

**None** — tylko gdy **świadomie** używasz wyłącznie SSH z agentem lub innego mechanizmu.

#### A1j. Krok „Configuring extra options”

- **Enable file system caching** — **zostaw włączone** (✓). Przyspiesza niektóre operacje Gita (`core.fscache`); **Cursor / agent** korzystają z tego samego `git` — bez wady dla typowej pracy.

- **Enable symbolic links** — **zwykle zostaw wyłączone** (bez ✓).  
  - Dotyczy **repozytoriów Gita**, które zawierają **symlinki** (np. projekty z Linuksa); wymaga uprawnienia Windows *SeCreateSymbolicLink* (czasem tryb dewelopera / admin).  
  - **Twoje junctiony** `mklink /J` do `reports_*` **nie zależą** od tej opcji — junction to osobna funkcja systemu, nie ten checkbox.

#### A1k. Ostatnie ekrany (po **Install**)

Zwykle zostaje już tylko:

- **Completing the Git Setup Wizard** — opcjonalnie odhacz *View Release Notes*; możesz zaznaczyć *Launch Git Bash*, jeśli chcesz.
- **Koniec** — otwórz **nowe** okno PowerShell i sprawdź: `git --version`.

**Dalsze kroki** nie są „kolejnymi pytaniami instalatora” — to już **§ B** tego dokumentu (`git init`, GitHub, `push`).

### Ściąga: wszystkie wybrane opcje (pod Cursor + Windows)

| Krok instalatora | Wybór |
|------------------|--------|
| Edytor | Notepad (lub VS Code / `core.editor` → Cursor) |
| Domyślna gałąź | **Override** → `main` |
| PATH | Git from cmdline + 3rd-party (**Recommended**) |
| SSH | **Bundled OpenSSH** |
| HTTPS | **Windows Secure Channel** |
| Końce linii | **Checkout Windows-style, commit Unix-style** (OK) lub *as-is / commit LF* |
| Terminal Git Bash | **MinTTY** (obojętne dla PowerShella w Cursorze) |
| `git pull` | **Fast-forward or merge** |
| Credential | **Git Credential Manager** |
| Extra | **File cache ON**; **symlinks OFF** (chyba że repo z symlinkami + uprawnienia) |

### A2. Konto GitHub

1. Wejdź na [github.com](https://github.com) → **Sign up** (jeśli nie masz konta).
2. Zaloguj się.

---

## Część B — pierwszy raz (repo: lokalne → GitHub)

### B1. Repo lokalne w folderze EA

W PowerShell:

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"

# Jeśli JESZCZE nie było git init:
git init
git add .
git status
git commit -m "chore: initial commit DailySessionLogger_v2"
```

Jeśli **już** masz `.git` i commity — pomiń `git init`, od razu `git status`.

### B2. Puste repo na GitHubie

1. GitHub → **New repository**.
2. Nazwa np. `DailySessionLogger_v2`.
3. **Bez** README / .gitignore z strony (masz już pliki lokalnie).
4. Utwórz repo — skopiuj URL, np.  
   `https://github.com/TWOJ_LOGIN/DailySessionLogger_v2.git`

### B3. Połączenie local → remote i pierwszy push

```powershell
cd "...DailySessionLogger_v2"

git remote add origin https://github.com/TWOJ_LOGIN/DailySessionLogger_v2.git
git branch -M main
git push -u origin main
```

- Przy **HTTPS** pierwszy raz Windows/Git Credential Manager zapyta o logowanie do GitHuba (lub **Personal Access Token** zamiast hasła — zalecane: GitHub → Settings → Developer settings → PAT).

Po sukcesie kod jest **lokalnie** i na **GitHubie**.

### B4. Typowy błąd: `fatal: not a git repository`

Ten komunikat pojawia się, gdy uruchamiasz `git commit` (lub `git status`) **nie w folderze projektu**, tylko np. w:

- `C:\Windows\System32` (PowerShell „jako Administrator” często startuje tu),
- `~` / `C:\Users\cewue` (Git Bash w katalogu domowym).

**Co zrobić:** przejdź do katalogu, w którym jest projekt (tam ma być folder `.git` po `git init`):

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
git status
```

Jeśli `git status` nadal mówi, że to nie repo — w tym folderze wykonaj **raz** `git init`, potem `git add` i `git commit` (jak w **B1**).

---

## Część C — codzienna praca (local + remote)

Typowy dzień:

```powershell
cd "...DailySessionLogger_v2"

# Opcjonalnie: ściągnij ewentualne zmiany z GitHuba (np. z drugiego PC)
git pull

# Gałąź robocza / backup przed większą zmianą
git checkout -b feature/krotki-opis
# ... edycje w Cursorze, kompilacja MT5 ...

git add .
git status
git commit -m "fix: krótki opis zmiany"

# Wypchnięcie na GitHub
git push -u origin feature/krotki-opis
```

Albo pracujesz na **`main`** (prościej, ale mniej izolacji):

```powershell
git add .
git commit -m "chore: opis"
git push
```

**Zasada:** przed ryzykowną zmianą — **`git checkout -b backup/2026-03-23-pre-...`** lub **`git tag`** na działającym commicie (patrz `GIT/README.md`).

---

## MetaEditor vs ten sam folder

- **Nie musisz** robić **Clone** w MT5 na tym samym PC, jeśli projekt **już leży** w `Experts\Advisors\DailySessionLogger_v2` i tam jest `.git`.
- **Clone** = nowy folder na dysku — przydatny na **drugim komputerze** albo gdy startujesz od zera z GitHuba.

---

## Cursor a GitHub po skonfigurowaniu

- Cursor nadal edytuje **lokalne pliki**.
- **Push/pull** = zwykły Git (terminal w Cursorze albo **Source Control**). Tokeny/SSH konfigurujesz **w systemie**, nie „w Cursorze osobno’’.

Jeśli `git push` zwraca błąd autoryzacji — sprawdź PAT lub zalogowanie w Git Credential Manager.
