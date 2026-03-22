# Junction `scripts_<LOGIN>` — wdrożenie skryptów MQL5 do właściwego terminala

## Po co to jest

Skrypt z `InpLogin = 10828174` musi być skompilowany i uruchomiony w **profilu MT5**, w którym jesteś zalogowany jako **10828174**.  
Folder `...\Terminal\<HASH>\MQL5\Scripts` jest **inny** dla każdej instalacji/profilu — nie wolno wrzucać wszystkich skryptów do jednego terminala (np. konta 11720331).

## Konwencja nazwy

| Element | Przykład |
|--------|----------|
| Junction w projekcie | `scripts_10828174` |
| Cel (rzeczywisty folder) | `...\Terminal\36F3667EB5BDDE97A477149EF2950EBB\MQL5\Scripts` |

Ta sama idea co **`logs_<LOGIN>`** — tylko że cel to **`MQL5\Scripts`**, nie `MQL5\Logs`.

## Gotowe komendy `New-Item` (PowerShell) — reconcile / inne konta

Uruchom **PowerShell w katalogu projektu** `DailySessionLogger_v2` (tam powstaną foldery `scripts_<LOGIN>`):

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
```

**10828174** (przykład taki jak podałeś — ścieżka docelowa = `MQL5\Scripts` tego terminala):

```powershell
New-Item -ItemType Junction -Path ".\scripts_10828174" -Target "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\36F3667EB5BDDE97A477149EF2950EBB\MQL5\Scripts"
```

**11693817:**

```powershell
New-Item -ItemType Junction -Path ".\scripts_11693817" -Target "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\89217B58689CB00C0846B58023D22F24\MQL5\Scripts"
```

**11720331:**

```powershell
New-Item -ItemType Junction -Path ".\scripts_11720331" -Target "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\88B1F5D567D7075232D98E392049CDB6\MQL5\Scripts"
```

**11693814** — **ten sam profil terminala** co na zrzucie (Explorer: `...\Terminal\49C33A939697AEF354FFC02653AB58DE\` z `MQL5`, `logs`, `config` itd.). Cel junctiona to **`MQL5\Scripts`** w tym folderze, **nie** lokalny katalog projektu:

```powershell
New-Item -ItemType Junction -Path ".\scripts_11693814" -Target "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Scripts"
```

Jeśli folder `scripts_<LOGIN>` **już istnieje** — usuń tylko dowiązanie (nie kasuje plików w terminalu), potem utwórz od nowa:

```powershell
cmd /c rmdir ".\scripts_10828174"
```

## Jak utworzyć junction (Windows, CMD jako admin lub z prawem do linków)

Przykład — dostosuj ścieżkę **docelową** do swojego MT5 (File → Open Data Folder → wyjdź do `MQL5\Scripts`):

```bat
mklink /J "C:\...\DailySessionLogger_v2\scripts_10828174" "C:\Users\...\Terminal\36F3667EB5BDDE97A477149EF2950EBB\MQL5\Scripts"
```

Potem dodaj folder `scripts_10828174` do workspace w Cursor (lub trzymaj go w katalogu projektu), żeby AI mógł **kopiować** tam `*.mq5` po edycji.

### Automatycznie (bez ręcznego wpisywania hash w ścieżkach)

Skrypt **`scripts/junctions/Create-ScriptsJunctions.ps1`** czyta cele junctionów **`logs_<LOGIN>_terminal`** lub **`logs_<LOGIN>`** i z nich buduje ścieżkę do **`...\MQL5\Scripts`**:

- standard: `...\Terminal\<HASH>\MQL5\Logs` → `...\MQL5\Scripts`;
- częsty wariant: `...\Terminal\<HASH>\Logs` (bez segmentu `MQL5` w ścieżce) → `...\Terminal\<HASH>\MQL5\Scripts`;
- usuwa prefix `\??\` ze ścieżki Win32, jeśli junction go zwraca.

Z katalogu **`DailySessionLogger_v2`** uruchom w PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\junctions\Create-ScriptsJunctions.ps1
```

- Lista loginów: **`$ReconcileLogins`** w **`scripts/junctions/Create-ScriptsJunctions.ps1`** — dopisz nowe konta.
- Podgląd (bez zmian na dysku):  
  `.\scripts\junctions\Create-ScriptsJunctions.ps1 -WhatIf`
- Nadpisanie istniejącego `scripts_<LOGIN>` (zły cel):  
  `.\scripts\junctions\Create-ScriptsJunctions.ps1 -Force`

**Uwaga:** junction **`logs_<LOGIN>`** musi wskazywać na **folder logów MT5** dla tego profilu (`...\MQL5\Logs` lub `...\Terminal\<HASH>\Logs`). Jeśli wskażesz np. lokalny folder `logs` w projekcie, skrypt wyliczy **błędny** `MQL5\Scripts` — wtedy popraw najpierw junction logów.

## Co robi AI (wg `.cursorrules_Scripts` §5b)

- Edycja źródła nadal w repo (np. `scripts_11720331_Reconcilled\[1]DailySessionReconcile_Delta_10828174.mq5`).
- Jeśli **`scripts_10828174`** jest widoczny w projekcie — **kopia pliku** do tego junctiona (nadpisanie).
- Jeśli junctiona nie ma — instrukcja utworzenia, **bez** fałszywego „już wrzucone do terminala”.

## Uwaga

Kompilacja **F7** i tak robisz w MetaEditorze w tym profilu — junction tylko zapewnia, że **właściwy plik** jest już we właściwym `Scripts`.

## Status w tym projekcie (weryfikacja)

- Folder **`scripts_10828174`** jest w katalogu `DailySessionLogger_v2` i wskazuje na **`MQL5\Scripts`** terminala konta **10828174** — agent może tu **nadpisywać** `[1]DailySessionReconcile_Delta_10828174.mq5` po edycji źródła.
- **`scripts_11693814`** / **`scripts_11693817`**: ten sam typ skryptu Stage A (`[1]DailySessionReconcile_Delta_<LOGIN>.mq5`), `InpLogin` ustawiony pod konto; wersja i logika zsynchronizowane (patrz `docs/CHANGE_LOG.md` **ID-18**).
- Szybki test w PowerShell (w katalogu projektu):  
  `Get-ChildItem -LiteralPath '.\scripts_10828174\[1]DailySessionReconcile_Delta_10828174.mq5'`

## Typowy błąd: `New-Item ... cannot be removed because it is not empty`

- Nie twórz drugiego junctiona pod **tą samą nazwą** (`logs`), jeśli już istnieje (albo usuń stary: `cmd /c rmdir logs` — usuwa tylko link, nie cel).
- **Nie** nazywaj junctiona do `Scripts` jako `logs` — użyj **`scripts_<LOGIN>`**, żeby nie mieszać z **`logs_<LOGIN>`** → `MQL5\Logs`.
