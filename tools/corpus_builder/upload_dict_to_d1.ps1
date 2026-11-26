<#
.SYNOPSIS
    FreeDict gerçek EN-TR sözlük anlamlarını D1 corpus_lexicon.meanings_json alanına yükler.
    (Mevcut examples_json film/dizi/Tatoeba alıntılarına dokunmaz.)
#>
param(
    [int]$StartBatch = 0,
    [switch]$Local
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$WorkerDir = Resolve-Path "$ScriptDir\..\ai_worker"
$BatchDir = "$ScriptDir\out\dict_batches"

if (-not (Test-Path $BatchDir)) {
    throw "Sözlük batch klasörü bulunamadı: $BatchDir. Önce 'node update_meanings_dict.mjs' çalıştırın."
}

$files = Get-ChildItem -Path $BatchDir -Filter "dict_batch_*.sql" | Sort-Object Name
if ($files.Count -eq 0) {
    throw "Yüklenecek dict_batch_*.sql dosyası bulunamadı."
}

$targetFlag = if ($Local) { "--local" } else { "--remote" }
Write-Host "`n==> Toplam $($files.Count) sözlük SQL dosyası Cloudflare D1'e ($targetFlag) yükleniyor..." -ForegroundColor Cyan

Push-Location $WorkerDir
try {
    $idx = -1
    foreach ($file in $files) {
        $idx++
        if ($idx -lt $StartBatch) { continue }
        Write-Host "[$($idx + 1)/$($files.Count)] Yükleniyor: $($file.Name)..." -NoNewline
        & npx wrangler d1 execute linereader-db $targetFlag --file="$($file.FullName)" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " HATA!" -ForegroundColor Red
            throw "Yükleme $($file.Name) dosyasında durdu. Devam etmek için: .\upload_dict_to_d1.ps1 -StartBatch $idx"
        }
        Write-Host " OK" -ForegroundColor Green
    }

    Write-Host "`nTamamlandı! Gerçek Türkçe anlamlar D1'e yüklendi (örnek cümleler korundu).`n" -ForegroundColor Green
}
finally {
    Pop-Location
}
