<#
.SYNOPSIS
    Line Reader Makale Paneli icin RTX 5060 (CUDA 12.8) uyumlu yerel Chatterbox TTS kurulum betigi.
#>
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$StudioDir = $PSScriptRoot
$VenvDir = Join-Path $StudioDir ".venv_chatterbox"
$VoicesDir = Join-Path $StudioDir "voices"

Write-Host "`n=== Line Reader — Chatterbox GPU TTS (RTX 5060) Kurulumu ===" -ForegroundColor Cyan

if (-not (Test-Path $VoicesDir)) {
    New-Item -ItemType Directory -Path $VoicesDir -Force | Out-Null
}

# 1) Python 3.11 bul veya winget ile kur
function Find-Python311 {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "C:\Python311\python.exe",
        "$env:ProgramFiles\Python311\python.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    try {
        $pyOut = & py -3.11 -c "import sys; print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $pyOut -and (Test-Path $pyOut.Trim())) {
            return $pyOut.Trim()
        }
    } catch {}
    return $null
}

$pythonExe = Find-Python311
if (-not $pythonExe) {
    Write-Host "`n==> 1. Python 3.11 bulunamadi, winget ile kuruluyor..." -ForegroundColor Yellow
    & winget install -e --id Python.Python.3.11 --accept-package-agreements --accept-source-agreements
    $pythonExe = Find-Python311
    if (-not $pythonExe) {
        throw "Python 3.11 kuruldu ancak bulunamadi. Lutfen yeni bir PowerShell penceresi acip .\install_chatterbox.ps1 komutunu tekrar calistirin."
    }
}
Write-Host "Python 3.11 bulundu: $pythonExe" -ForegroundColor Green

# 2) Izole sanal ortam (.venv_chatterbox) olustur
if (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
    Write-Host "`n==> 2. Sanal ortam olusturuluyor (.venv_chatterbox)..." -ForegroundColor Cyan
    & $pythonExe -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { throw "Sanal ortam olusturulamadi." }
}

$venvPython = Join-Path $VenvDir "Scripts\python.exe"
$venvPip = Join-Path $VenvDir "Scripts\pip.exe"

Write-Host "`n==> 3. pip guncelleniyor..." -ForegroundColor Cyan
& $venvPython -m pip install --upgrade pip setuptools wheel

# 3) Chatterbox TTS kur
Write-Host "`n==> 4. Chatterbox TTS kuruluyor..." -ForegroundColor Cyan
& $venvPip install chatterbox-tts
if ($LASTEXITCODE -ne 0) { throw "chatterbox-tts kurulumu basarisiz oldu." }

# 4) RTX 5060 (Blackwell sm_120) uyumlu PyTorch CUDA 12.8'i ustune zorla kur (chatterbox'in CPU torch'unu ezer)
Write-Host "`n==> 5. RTX 5060 uyumlu PyTorch (CUDA 12.8) kuruluyor..." -ForegroundColor Cyan
& $venvPip install --upgrade --force-reinstall --no-deps torch torchaudio --index-url https://download.pytorch.org/whl/cu128
if ($LASTEXITCODE -ne 0) { throw "PyTorch CUDA 12.8 kurulumu basarisiz oldu." }

# 5) GPU dogrulamasi
Write-Host "`n==> 6. RTX 5060 CUDA dogrulamasi yapiliyor..." -ForegroundColor Cyan
& $venvPython -c "import torch; print('CUDA Hazir:', torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')"

Write-Host "`nKurulum basariyla tamamlandi!" -ForegroundColor Green
Write-Host "Simdi Makale_Panelini_Ac.bat ile paneli acip 'Chatterbox GPU (RTX 5060)' secenegini kullanabilirsin." -ForegroundColor Green
Write-Host "Not: Kendi ozel sesini klonlamak istersen 10 saniyelik temiz bir .wav dosyasini '$VoicesDir\custom.wav' olarak koyabilirsin.`n" -ForegroundColor DarkGray
