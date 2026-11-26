<#
.SYNOPSIS
    Hazırlanan corpus_lexicon SQL parçalarını Cloudflare D1 (linereader-db) veri tabanına yükler.
#>
param(
    [int]$StartBatch = 1,
    [switch]$Local
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$WorkerDir = Resolve-Path "$ScriptDir\..\ai_worker"
$BatchDir = "$ScriptDir\out\d1_batches"

if (-not (Test-Path $BatchDir)) {
    throw "SQL batch klasörü bulunamadı: $BatchDir. Önce 'node build_lexicon_corpus.mjs' çalıştırın."
}

$files = Get-ChildItem -Path $BatchDir -Filter "batch_*.sql" | Sort-Object Name
if ($files.Count -eq 0) {
    throw "Yüklenecek batch_*.sql dosyası bulunamadı."
}

$targetFlag = if ($Local) { "--local" } else { "--remote" }
Write-Host "`n==> Toplam $($files.Count) SQL parçası Cloudflare D1'e ($targetFlag) yükleniyor..." -ForegroundColor Cyan

Push-Location $WorkerDir
try {
    # Önce corpus_lexicon tablosunun var olduğundan emin ol
    $schemaSql = "CREATE TABLE IF NOT EXISTS corpus_lexicon (word TEXT PRIMARY KEY, meanings_json TEXT NOT NULL DEFAULT '[]', examples_json TEXT NOT NULL DEFAULT '[]', freq_rank INTEGER NOT NULL DEFAULT 999999, updated_at TEXT NOT NULL); CREATE INDEX IF NOT EXISTS idx_corpus_lexicon_rank ON corpus_lexicon(freq_rank);"
    & npx wrangler d1 execute linereader-db $targetFlag --command="$schemaSql"
    if ($LASTEXITCODE -ne 0) { throw "Şema oluşturma başarısız!" }

    $idx = 0
    foreach ($file in $files) {
        $idx++
        if ($idx -lt $StartBatch) { continue }
        Write-Host "[$idx/$($files.Count)] Yükleniyor: $($file.Name)..." -NoNewline
        & npx wrangler d1 execute linereader-db $targetFlag --file="$($file.FullName)" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " HATA!" -ForegroundColor Red
            throw "Yükleme $idx. dosyada ($($file.Name)) durdu. Devam etmek için: .\upload_to_d1.ps1 -StartBatch $idx"
        }
        Write-Host " OK" -ForegroundColor Green
    }

    Write-Host "`nTamamlandı! Tüm OpenSubtitles & Tatoeba verileri linereader-db'ye aktarıldı.`n" -ForegroundColor Green
}
finally {
    Pop-Location
}
