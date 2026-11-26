<#
.SYNOPSIS
    Line Reader Cloudflare Worker köprüsünü günceller, Web uygulamasını derler,
    content/app klasörüne kopyalar ve GitHub'a push eder.
#>
param(
    [string]$CommitMessage = "feat: add dictionary proxy and web cors support"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = $PSScriptRoot
Push-Location $ProjectRoot
try {
    # 1) Cloudflare Worker'ı güncelle (CORS engelsiz /dict sözlük köprüsü)
    Write-Host "`n==> 1. Cloudflare Worker dağıtılıyor (linereader-ai)..." -ForegroundColor Cyan
    try {
        Push-Location "$ProjectRoot\tools\ai_worker"
        & npx wrangler deploy
    } catch {
        Write-Host "Wrangler uyarısı: $_" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }

    # 2) Flutter Web derlemesi
    Write-Host "`n==> 2. Flutter Web derleniyor (base-href: /app/)..." -ForegroundColor Cyan
    & flutter build web --base-href /app/ --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter web derleme hatası!" }

    # 3) Dosyaları content/app içine taşı
    Write-Host "`n==> 3. build/web dosyaları content/app klasörüne kopyalanıyor..." -ForegroundColor Cyan
    Copy-Item -Path "$ProjectRoot\build\web\*" -Destination "$ProjectRoot\content\app" -Recurse -Force

    # 4) Git'e ekle ve GitHub'a push et
    Write-Host "`n==> 4. Değişiklikler Git'e ekleniyor ve GitHub'a push ediliyor..." -ForegroundColor Cyan
    & git add .
    & git commit -m $CommitMessage
    & git push origin main
    if ($LASTEXITCODE -ne 0) { throw "Git push hatası!" }

    Write-Host "`nBaşarılı! Hem Cloudflare Worker hem de Web sitesi güncellendi.`n" -ForegroundColor Green
}
finally {
    Pop-Location
}
