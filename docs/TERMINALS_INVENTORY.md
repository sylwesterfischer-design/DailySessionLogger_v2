# Inventory terminali MT5 — `Terminal\<HASH>` ↔ konto

**Źródło junctionów do repo:** `d:\Trading\_kopiarka\symlink.txt` (lub kopia w repo — dopisz ścieżkę, jeśli przenosisz plik).

**Rejestr logów / folderów w Explorerze:** `docs/trading_accounts_mt5.md`.

**Uwaga:** hash `Terminal\<HASH>` to **ID instalacji MT5**, nie login brokera. Login bierz z MT5 albo z tabeli poniżej (tam gdzie spięte z Twoją nomenklaturą).

---

## MASTER — źródło `DailySessionLogger_v2`

| Terminal ID (`Terminal\...`) | Etykieta (Twoje) | Typowy login (wg `trading_accounts_mt5.md`) | Rola |
|------------------------------|------------------|---------------------------------------------|------|
| `49C33A939697AEF354FFC02653AB58DE` | **MASTER 814k** (repo) | **11693814** (folder `DEMO-07_814`) | **Cel** wszystkich `mklink /J ... DailySessionLogger_v2` w `symlink.txt`; tutaj żyje kanoniczna kopia projektu pod `MQL5\Experts\Advisors\`. |

---

## Instalacje docelowe — junction → MASTER

W `symlink.txt` każdy wiersz `mklink` robi **link z tego terminala** do folderu MASTER `49C33…`.

| Etykieta w notatce | Terminal ID (`Terminal\...`) | Login (wg tabeli kont / końcówki) | Uwagi |
|--------------------|------------------------------|-----------------------------------|--------|
| **931-Live** | `0E812ED0A250D901020B93B704737346` | **10849931** | LIVE / `LiveMaster-10849931`; **sprawdź**, czy folder `DailySessionLogger_v2` jest junctionem do `49C33…` (wcześniej zdarzała się zwykła kopia). |
| **890** | `C67B5770548890B5F7D25C37E37510D4` | **10827890** | DEMO `_890` |
| **887** | `11323AE50255BE2254C1063A8FDDB645` | **10827887** | DEMO `_887` |
| **817** | `89217B58689CB00C0846B58023D22F24` | **11693817** | DEMO `_817` |
| **331** | `88B1F5D567D7075232D98E392049CDB6` | **11720331** | DEMO `_331` |
| **867** | `136EABB4DE5E9B44E4EC623D0DC18EA5` | **11754867** | DEMO `_867` |
| **456** | `5E57C93DEE0D3360D5CCC98B364A2533` | *(MT5)* / **11754456** (arkusz) | `DEMO-11_456` — pełny login tylko z MT5 / arkusza |
| **824** | `CA614DB8CAC05F3F4EA3B66049E59C0E` | **824** (EUR demo) | Weryfikuj pełny login w MT5 |
| **764** | `C0B57A3DF121356571EC2728359358EB` | **10934764** | końcówka **764** |
| **585** | `A0006A14A3B3C3E1CC40DA03E8A94635` | **10957585** | końcówka **585** |
| **174** | `36F3667EB5BDDE97A477149EF2950EBB` | **10828174** | końcówka **174** |

---

## Utrzymanie

1. Nowa kopia MT5 → **Plik → Otwórz folder danych** → skopiuj fragment ścieżki `...\Terminal\<HASH>\`.
2. Dopisz wiersz w `d:\Trading\_kopiarka\symlink.txt` + tutaj w tabeli.
3. Zaktualizuj `docs/trading_accounts_mt5.md` (§1d.8).

**Ostatnia synchronizacja z `symlink.txt`:** 2026-03-27
