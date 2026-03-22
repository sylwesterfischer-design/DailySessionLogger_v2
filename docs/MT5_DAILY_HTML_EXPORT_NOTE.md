# Czy Cursor może o 23:59:59 sam pobrać raport HTML z MT5 do junction?

**Krótko: nie — Cursor nie jest harmonogramem ani częścią MetaTradera.**

## Dlaczego

- **Cursor** (edytor + agent AI) **nie działa w tle** jako usługa o ustalonej godzinie i **nie ma API** do sterowania oknem MT5 ani do klikania *Raport → HTML*.
- **Eksport HTML** z MT5 (jak na zrzucie: prawy przycisk → **Raport** → **HTML**) to akcja **klienta MT5** — do automatyzacji trzeba innego mechanizmu.

## Zaimplementowane w repo

- EA **`ExportDailyHistoryHtml.mq5`** — codzienny zapis HTML dealów do `Common\Files\<podfolder>` + **junction** do `reports_<LOGIN>` w repo. Szczegóły: **`docs/EXPORT_DAILY_HTML_JUNCTIONS.md`**.

## Inne kierunki (poza Cursorem)

| Podejście | Uwagi |
|-----------|--------|
| **Własny EA** (powyżej) | Timer 23:59 (serwer); własny HTML zgodny z `--layout deals-default`; **nie** zapis poza `Common\Files` bez junction. |
| **Ręczny eksport + junction** | Raport zapisujesz ręcznie / po sesji do folderu, który jest **junctionem** do `reports_<LOGIN>\` w repo — jak teraz. |
| **Zewnętrzna automatyzacja UI** | AutoHotkey / skrypt sterujący oknem — kruche (rozdzielczość, język UI), **nie polecane** jako „produkcyjne” bez utrzymania. |

Jeśli w przyszłości zdefiniujesz **wymagany format** (np. własny CSV zamiast HTML z menu), można to zaplanować w **EA** bez udziału Cursora.

**Ten dokument nie zmienia schematów CSV EA** — dotyczy wyłącznie procesu eksportu raportu z MT5.
