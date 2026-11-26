<#
.SYNOPSIS
    Line Reader Web uygulamasını derler, content/app klasörüne kopyalar ve GitHub'a push eder.
    Cloudflare Pages GitHub'a push yapıldığında siteyi otomatik olarak günceller.
#>
param(
    [string]$CommitMessage = "feat(web): update add word screen and profile enhancements"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = $PSScriptRoot
Push-Location $ProjectRoot
try {
    Write-Host "`n==> 1. Flutter Web derleniyor (base-href: /app/)..." -ForegroundColor Cyan
    & flutter build web --base-href /app/ --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter web derleme hatası!" }

    Write-Host "`n==> 2. build/web dosyaları content/app klasörüne kopyalanıyor..." -ForegroundColor Cyan
    Copy-Item -Path "$ProjectRoot\build\web\*" -Destination "$ProjectRoot\content\app" -Recurse -Force

    Write-Host "`n==> 3. Değişiklikler Git'e ekleniyor ve GitHub'a push ediliyor..." -ForegroundColor Cyan
    & git add .
    & git commit -m $CommitMessage
    & git push origin main
    if ($LASTEXITCODE -ne 0) { throw "Git push hatası!" }

    Write-Host "`nBaşarılı! GitHub'a gönderildi. Cloudflare Pages 1-2 dakika içinde getlinereader.com/app adresini otomatik güncelleyecektir.`n" -ForegroundColor Green
}
finally {
    Pop-Location
}
