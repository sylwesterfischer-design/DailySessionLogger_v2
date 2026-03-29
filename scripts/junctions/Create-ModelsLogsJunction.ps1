# Junction: folder models_logs w profilu docelowym (Excel + ocr_state) <-> drugi profil MT5 / Cursor.
# Ustaw $Target (fizyczny katalog) i $Link (junction w repo, z ktorego odpalasz Pythona), potem:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
#   .\scripts\junctions\Create-ModelsLogsJunction.ps1

$ErrorActionPreference = "Stop"

# --- EDYTUJ TE DWIE SCIEZKI ---
$Target = "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\0E812ED0A250D901020B93B704737346\MQL5\Experts\Advisors\DailySessionLogger_v2\models_logs"
$Link   = "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2\models_logs"
# ------------------------------

New-Item -ItemType Directory -Force -Path $Target | Out-Null

if (Test-Path $Link) {
    $item = Get-Item $Link -Force
    if ($item.LinkType -eq "Junction") {
        Write-Host "Juz junction: $Link -> $($item.Target)"
        exit 0
    }
    if ($item.PSIsContainer) {
        throw "Istnieje zwykly folder (nie junction): $Link — przenies dane lub zmien nazwe, potem uruchom ponownie."
    }
    throw "Sciezka istnieje i nie jest katalogiem: $Link"
}

New-Item -ItemType Junction -Path $Link -Target $Target
Write-Host "OK: $Link -> $Target"
