<#
.SYNOPSIS
    Line Reader Makale Paneli icin RTX 5060 (CUDA 12.8) uyumlu F5-TTS Diffusion kurulum betigi.
#>
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$StudioDir = $PSScriptRoot
$VenvDir = Join-Path $StudioDir ".venv_f5tts"
$VoicesDir = Join-Path $StudioDir "voices"

Write-Host "`n=== Line Reader — F5-TTS Diffusion (RTX 5060) Kurulumu ===" -ForegroundColor Cyan

if (-not (Test-Path $VoicesDir)) {
    New-Item -ItemType Directory -Path $VoicesDir -Force | Out-Null
}

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
    throw "Python 3.11 bulunamadi. Once .\install_chatterbox.ps1 veya Python 3.11 kurun."
}
Write-Host "Python 3.11 bulundu: $pythonExe" -ForegroundColor Green

if (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
    Write-Host "`n==> 1. Izole sanal ortam olusturuluyor (.venv_f5tts)..." -ForegroundColor Cyan
    & $pythonExe -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { throw "Sanal ortam olusturulamadi." }
}

$venvPython = Join-Path $VenvDir "Scripts\python.exe"
$venvPip = Join-Path $VenvDir "Scripts\pip.exe"

Write-Host "`n==> 2. pip guncelleniyor..." -ForegroundColor Cyan
& $venvPython -m pip install --upgrade pip setuptools wheel

Write-Host "`n==> 3. f5-tts kuruluyor..." -ForegroundColor Cyan
& $venvPip install f5-tts scipy
if ($LASTEXITCODE -ne 0) { throw "f5-tts kurulumu basarisiz oldu." }

Write-Host "`n==> 4. RTX 5060 (CUDA 12.8) uyumlu PyTorch zorla kuruluyor..." -ForegroundColor Cyan
& $venvPip install --upgrade --force-reinstall --no-deps torch torchaudio --index-url https://download.pytorch.org/whl/cu128
if ($LASTEXITCODE -ne 0) { throw "PyTorch CUDA 12.8 kurulumu basarisiz oldu." }

Write-Host "`n==> 5. RTX 5060 CUDA dogrulamasi yapiliyor..." -ForegroundColor Cyan
& $venvPython -c "import torch; print(torch.__version__, 'CUDA:', torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')"

Write-Host "`nF5-TTS kurulumu basariyla tamamlandi!" -ForegroundColor Green
Write-Host "Simdi Makale_Panelini_Ac.bat ile paneli acip 'F5-TTS Diffusion (RTX 5060)' secenegini deneyebilirsin.`n" -ForegroundColor Green
