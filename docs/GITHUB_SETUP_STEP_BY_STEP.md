# Git lokalny + GitHub (remote) — krok po kroku

Folder projektu (u Ciebie):  
`...\MQL5\Experts\Advisors\DailySessionLogger_v2`

**Cursor nie instaluje Gita ani nie zakłada konta GitHub za Ciebie** — to robisz Ty w przeglądarce / instalatorze. Cursor potem edytuje **ten sam folder** i robi `commit` jak zwykle.

### Konwencja: w czym uruchamiać polecenia z tego dokumentu

| Środowisko | Kiedy |
|------------|--------|
| **PowerShell** (Windows, także **jako Administrator** jeśli już tak pracujesz) | Domyślnie: `cd`, `git`, `where.exe` — przykłady poniżej są pod PowerShell. |
| **Git Bash (MINGW64)** | Te same komendy `git`; ścieżki zapisuj jako `/c/Users/...` zamiast `C:\Users\...`. |
| **Zintegrowany terminal Cursora** | Zwykle PowerShell — **te same** polecenia co w tabeli, po `cd` do roota repo. |
| **Przeglądarka** | Tylko kroki **B2** (tworzenie repo na github.com). |
| **MetaEditor** | Kompilacja `.mq5` — **poza** tym dokumentem; przed `git commit` wg reguł projektu. |

### Twój profil Gita (ustalone ze screenów konfiguracji)

| Ustawienie | Wartość (Twoje) |
|------------|-----------------|
| `git config --global user.name` | **Sylwester Fischer** |
| `git config --global user.email` | **Sylwester.Fischer@gmail.com** |
| **Login GitHub** (URL `github.com/<login>/…`) | **`sylwesterfischer-design`** — ustawienia konta pokazują ten sam identyfikator w nawiasie; **nie** `sylwester-fischer` (inny adres = zły `remote`, `push` może wisieć lub kończyć się błędem). |

**Czy `user.name` musi być takie samo jak login GitHub?** **Nie.**  
`git config user.name` / `user.email` to **podpis autora w commicie** (np. „Sylwester Fischer”). **Login GitHub** (`sylwesterfischer-design`) służy tylko do **URL** i logowania przy `push`. GitHub przypisuje commity do konta głównie przez **e-mail** — dodaj **Sylwester.Fischer@gmail.com** w GitHub → **Settings → Emails** (i ewentualnie zweryfikuj), wtedy avatary/statystyki się zgadzają. **Nie ustawiaj** `user.name` na `sylwesterfischer-design`, chyba że **świadomie** chcesz takiego podpisu w historii.

**Przykładowy `remote` HTTPS dla tego projektu:**  
`https://github.com/sylwesterfischer-design/DailySessionLogger_v2.git`  
Jeśli dodałeś `origin` ze **złym** loginem, popraw: `git remote set-url origin <poprawny_URL>` (§ B3).

**Ogólnie (inni użytkownicy dokumentu):** login GitHub to **osobna** rzecz od `user.name` — sprawdź w **Settings → Public profile** lub w URL profilu (nie myl z `C:\Users\…` na Windows).

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

**Żeby commity z terminala otwierały się w Cursorze** (po instalacji Gita), **środowisko: PowerShell** (lub Git Bash — te same linie `git config`):

```powershell
git config --global core.editor "cursor --wait"
```

**Brak jakiegokolwiek komunikatu po tej komendzie = zwykle OK** (Git przy sukcesie nic nie drukuje). Sprawdź (**środowisko: PowerShell**):

```powershell
git config --global --get core.editor
```

Oczekiwany wynik: `cursor --wait`.  
Dalej upewnij się, że Windows widzi `cursor` (**środowisko: PowerShell** — `where.exe` to polecenie Windows):

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

# Tożsamość autora — Git wymaga tego przed pierwszym commit (to NIE jest logowanie do GitHuba):
git config --global user.name "Twoje Imię lub nick"
git config --global user.email "twoj_email@example.com"

git add .
git status
git commit -m "chore: initial commit DailySessionLogger_v2"
```

Jeśli **już** masz `.git` i commity — pomiń `git init`, od razu `git status`.  
Jeśli `user.name` / `user.email` masz już ustawione globalnie (`git config --global --list`), **nie musisz** ich powtarzać.

### B1a. Ostrzeżenia `LF will be replaced by CRLF` przy `git add`

Na **Windows**, przy typowym ustawieniu **checkout CRLF / commit LF** (`core.autocrlf`), Git przy `git add` często wypisuje:

`warning: in the working copy of '...', LF will be replaced by CRLF the next time Git touches it`

**To jest typowe i zwykle OK** — informacja, że końce linii będą normalizowane zgodnie z konfiguracją. Nie blokuje `git add` ani `git commit`.

### B1b. Komunikat „Author identity unknown” (nie „not authorized”)

Jeśli `git commit` kończy się tekstem w stylu **„Please tell me who you are”** / **„Author identity unknown”**, to znaczy, że **nie ustawiłeś** `user.name` i `user.email` (patrz blok w **B1**).  
**To nie ma nic wspólnego** z odmową dostępu do GitHuba — do GitHuba logujesz się dopiero przy **`git push`** (Credential Manager / token).

### B2. Puste repo na GitHubie

1. GitHub → **New repository**.
2. Nazwa np. `DailySessionLogger_v2`.
3. **Bez** README / .gitignore z strony (masz już pliki lokalnie).
4. Kliknij **Create repository** — dopiero wtedy GitHub **tworzy stronę** pod adresem `https://github.com/<login>/<nazwa>/`.  
5. Na stronie nowego repozytorium skopiuj URL (**HTTPS**).  
   **Uwaga:** placeholdery typu `TWOJ_LOGIN` to tylko **wzór** — nie wklejaj dosłownie. Login bierz z Settings → Public profile (u Ciebie: **`sylwesterfischer-design`**).

### B2a. Przeglądarka pokazuje **404** na `github.com/.../DailySessionLogger_v2`

**Najczęstsza przyczyna:** repozytorium **jeszcze nie zostało utworzone** na GitHubie (**B2**). Samo `git remote` i `git push` **nie tworzy** konta ani pustego repo — najpierw musi istnieć pusta strona repo po **New repository → Create repository**.

Inne możliwości:

| Objaw | Co sprawdzić |
|--------|----------------|
| **404** po wejściu w URL | Czy wykonałeś **Create repository** na koncie **`sylwesterfischer-design`** i nazwa to dokładnie **`DailySessionLogger_v2`** (wielkość liter)? |
| **404** mimo że repo jest | Czy jesteś **zalogowany** w tej samej przeglądarce na **sylwesterfischer-design**? Dla **prywatnego** repo obcy / wylogowany też często widzi **404** (GitHub tak maskuje dostęp). |
| `git push` bez końca / brak outputu | Okno **Git Credential Manager** / logowanie w **przeglądarce** — sprawdź pasek zadań; **Ctrl+C** przerywa. Potem **`git push -v origin main`** — zobaczysz więcej diagnostyki. |
| `repository not found` / `403` w terminalu | Zły URL, brak uprawnień, lub **nie** to konto co właściciel repo — PAT / login. |

**Kolejność poprawna:** **B2** (strona repo już istnieje w przeglądarce) → **B3** (`set-url` / `push`). Jeśli **B2** pominąłeś — zrób je teraz; po **Create** odśwież URL w przeglądarce.

### B3. Połączenie local → remote i pierwszy push

**Środowisko: PowerShell** albo **Git Bash (MINGW64)** — **obojętne**; to te same komendy `git`. Poniżej: PowerShell + ścieżka Windows. W Git Bash: `cd /c/Users/cewue/AppData/Roaming/.../DailySessionLogger_v2`.

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"

# Najprościej: wklej CAŁY adres HTTPS skopiowany z strony repo na GitHubie (Quick setup).
# Albo złóż URL: nazwę profilu bierz z paska adresu po wejściu na swój profil (nagłówek „Twój profil Gita” w tym dokumencie):
git remote add origin https://github.com/<GITHUB_LOGIN>/DailySessionLogger_v2.git
git branch -M main
git push -u origin main
```

**Przykład struktury** (wstaw **swoją** nazwę z GitHuba): `https://github.com/<GITHUB_LOGIN>/DailySessionLogger_v2.git` — **nie** używaj dosłownego tekstu `TWOJ_LOGIN` / `TWOJA_PRAWDZIWA_NAZWA` z tutoriali innych niż ten plik.

- Jeśli **`git remote add`** zwróci, że `origin` już istnieje: `git remote remove origin`, potem ponów `add` z poprawnym URL (albo **`git remote set-url origin <poprawny_URL>`** — najprościej po pomyłce w loginie GitHub).
- Przy **HTTPS** pierwszy raz Windows/**Git Credential Manager** może otworzyć **okno logowania w przeglądarce** albo **czekać w tle** — jeśli `git push` „wisi” bez tekstu, sprawdź **inne okna** (przeglądarka, małe okno Windows). **Ctrl+C** przerywa push.
- Przy **HTTPS** logowanie do GitHuba (lub **Personal Access Token** zamiast hasła — zalecane: GitHub → Settings → Developer settings → PAT).

Po sukcesie kod jest **lokalnie** i na **GitHubie**.

### B3b. `HTTP 408`, `RPC failed`, `remote end hung up` przy `git push`

Zdarza się, gdy **pierwszy push** wysyła **duży pakiet** (u Ciebie log pokazał ok. **274 MiB**) — timeout połączenia HTTP zanim GitHub przyjmie całość.

**Środowisko: PowerShell** — spróbuj **najpierw** (raz na PC):

```powershell
git config --global http.postBuffer 524288000
```

(`524288000` ≈ 500 MB; przy potrzebie możesz spróbować `1048576000` ≈ 1 GB.)

Potem w folderze repo ponów:

```powershell
git push -u origin main
```

Dodatkowo: **stabilne Wi‑Fi / kabel**, wyłączenie VPN na czas push, ewentualnie **ponowienie** po chwili (czasem chwilowa sieć).

**Uwaga:** wpisy w **`.gitignore`** działają od **następnych** commitów — nie usuwają plików już zapisanych w **obecnym** commicie. W repo jest `.gitignore` ignorujący m.in. **`*.mp4` / `*.m4a`** (żeby kolejne wersje nie puchły). Jeśli **pierwszy push** dalej się nie udaje mimo bufora, duże pliki są już w historii lokalnej — wtedy albo **wielokrotne próby** push, albo osobna robota: usunięcie ich z historii (`git filter-repo` / BFG) — to dopiero na prośbę, bo zmienia historię.

### B3c. `GH001: Large files detected` / `pre-receive hook declined` — na GitHubie **nie ma** gałęzi `main`

GitHub **nie tworzy** `main` na serwerze, dopóki **pierwszy push nie przejdzie w całości**. Komunikat **`remote: error: GH001`** = odrzucenie: w paczce są pliki **za duże**.

**Limity (typowe):**

- **> 100 MB** pojedynczy plik → **twardy błąd**, push **odrzucony** (np. wideo `.mp4`).
- **> 50 MB** → ostrzeżenie; nadal możliwy push, ale lepiej nie trzymać takich plików w repo.

**Przykład z tego projektu (ścieżki z logu GitHuba):**  
`trading_strategy/A1.mp4` (~261 MB), `reports_*/ReportHistory-*.html` (dziesiąki MB).

**Środowisko: PowerShell** — usuń te pliki **z indeksu Gita** (na dysku mogą zostać), zaktualizuj `.gitignore` (w repo jest już m.in. **`reports_*/`**, **`trading_strategy/`** i **`*.mp4`**), potem **popraw historię**:

1. Sprawdź liczbę commitów: `git log --oneline`  
   - **Jeśli jest dokładnie jeden** commit (typowy pierwszy `initial`):

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"

git rm --cached "trading_strategy/A1.mp4" 2>$null
git rm --cached "reports_10827887/ReportHistory-10827887.html" 2>$null
git rm --cached "reports_10828174/ReportHistory-10828174.html" 2>$null

git add .gitignore
git commit --amend -m "chore: initial commit DailySessionLogger_v2"
git push -u origin main
```

   - **Jeśli commitów jest więcej** — same `git rm --cached` + nowy commit **nie wystarczą** (stary commit nadal zawiera duże bloby). Trzeba **przepisać historię** (`git filter-repo`, BFG) albo zacząć repo od zera — wtedy dopytaj lub skorzystaj z dokumentacji GitHub „Removing sensitive data”.

2. Po **udanym** pushu strona repo pokaże gałąź **`main`** i pliki.

### B4. Typowy błąd: `fatal: not a git repository`

Ten komunikat pojawia się, gdy uruchamiasz `git commit` (lub `git status`) **nie w folderze projektu**, tylko np. w:

- `C:\Windows\System32` (PowerShell „jako Administrator” często startuje tu),
- `~` / `C:\Users\cewue` (Git Bash w katalogu domowym).

**Co zrobić:** przejdź do katalogu, w którym jest projekt (tam ma być folder `.git` po `git init`). **Środowisko: PowerShell** (lub Git Bash z ekwiwalentem ścieżki):

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
git status
```

Jeśli `git status` nadal mówi, że to nie repo — w tym folderze wykonaj **raz** `git init`, potem `git add` i `git commit` (jak w **B1**).

---

## Część C — codzienna praca (local + remote)

**Środowisko: PowerShell** (lub Git Bash + ścieżka `/c/Users/...`).

Typowy dzień:

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"

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
