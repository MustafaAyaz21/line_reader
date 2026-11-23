<#
.SYNOPSIS
    Line Reader otomatik sürüm artırma, imzalı APK derleme, version.json güncelleme,
    GitHub'a push ve GitHub Release yayınlama betiği.

.EXAMPLE
    .\release.ps1
    .\release.ps1 -Notes "Yeni tarayıcı iyileştirmeleri ve hata düzeltmeleri."
    .\release.ps1 -BumpType minor -Notes "Yeni özellikler eklendi."
#>
param(
    [ValidateSet("patch", "minor", "major")]
    [string]$BumpType = "patch",
    [string]$Notes = "Performans iyileştirmeleri ve hata düzeltmeleri.",
    [int]$MinVersionCode = 0
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoSlug = "MustafaAyaz21/line_reader"
$RemoteUrl = "https://github.com/$RepoSlug.git"
$ProjectRoot = $PSScriptRoot
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$VersionJsonPath = Join-Path $ProjectRoot "version.json"
$KeyPropertiesPath = Join-Path $ProjectRoot "android\key.properties"
$KeystorePath = Join-Path $ProjectRoot "android\app\line-reader-key.jks"
$ApkPath = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

Push-Location $ProjectRoot
try {
    # 1) Ön kontroller: imzalama anahtarı ve key.properties doğrulaması
    Write-Step "İmzalama ve proje dosyaları kontrol ediliyor..."
    if (-not (Test-Path $PubspecPath)) {
        throw "pubspec.yaml bulunamadı: $PubspecPath"
    }
    if (-not (Test-Path $KeystorePath)) {
        throw "İmzalama anahtarı bulunamadı: $KeystorePath"
    }
    if (-not (Test-Path $KeyPropertiesPath)) {
        throw "android/key.properties bulunamadı."
    }

    $keyPropsContent = Get-Content -Path $KeyPropertiesPath -Raw -Encoding UTF8
    if ($keyPropsContent -match "\[KULLANDIĞIN_PAROLA\]") {
        throw "Lütfen önce android/key.properties dosyasındaki [KULLANDIĞIN_PAROLA] alanını gerçek anahtar parolanızla değiştirin."
    }

    # 2) pubspec.yaml içindeki sürüm ve build numarasını (+1) artır
    Write-Step "pubspec.yaml sürüm ve build numarası artırılıyor..."
    $pubspecRaw = Get-Content -Path $PubspecPath -Raw -Encoding UTF8
    $versionMatch = [regex]::Match($pubspecRaw, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)(?=\r?$)')
    if (-not $versionMatch.Success) {
        throw "pubspec.yaml içinde 'version: X.Y.Z+B' satırı bulunamadı."
    }

    $major = [int]$versionMatch.Groups[1].Value
    $minor = [int]$versionMatch.Groups[2].Value
    $patch = [int]$versionMatch.Groups[3].Value
    $buildNumber = [int]$versionMatch.Groups[4].Value

    switch ($BumpType) {
        "major" { $major++; $minor = 0; $patch = 0 }
        "minor" { $minor++; $patch = 0 }
        default { $patch++ }
    }
    $newBuildNumber = $buildNumber + 1
    $newVersion = "$major.$minor.$patch"
    $newFullVersion = "$newVersion+$newBuildNumber"

    $updatedPubspec = [regex]::Replace(
        $pubspecRaw,
        '(?m)^version:\s*\d+\.\d+\.\d+\+\d+(?=\r?$)',
        "version: $newFullVersion",
        1
    )
    Write-Utf8NoBom -Path $PubspecPath -Content $updatedPubspec
    Write-Host "Yeni sürüm: v$newVersion (version_code: $newBuildNumber)" -ForegroundColor Green

    # 3) Bağımlılıkları al ve hafif 64-bit (arm64-v8a) imzalı release APK derle
    Write-Step "İmzalı release APK derleniyor (flutter build apk --release --target-platform android-arm64)..."
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get başarısız oldu." }

    & flutter build apk --release --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk --release başarısız oldu." }

    if (-not (Test-Path $ApkPath)) {
        throw "Derlenen APK bulunamadı: $ApkPath"
    }

    # 4) version.json dosyasını güncelle
    Write-Step "version.json güncelleniyor..."
    $apkDownloadUrl = "https://github.com/$RepoSlug/releases/download/v$newVersion/app-release.apk"
    $versionObject = [ordered]@{
        latest_version   = $newVersion
        version_code     = $newBuildNumber
        min_version_code = $MinVersionCode
        apk_url          = $apkDownloadUrl
        release_notes    = $Notes
    }
    $versionJsonText = ($versionObject | ConvertTo-Json -Depth 4) + "`n"
    Write-Utf8NoBom -Path $VersionJsonPath -Content $versionJsonText

    # 5) Git deposu, uzak depo (origin) ve gizli dosya kontrolü + push
    Write-Step "GitHub deposu güncelleniyor..."
    if (-not (Test-Path (Join-Path $ProjectRoot ".git"))) {
        & git init
        & git branch -M main
    }

    $existingOrigin = (& git remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($existingOrigin)) {
        & git remote add origin $RemoteUrl
    } elseif ($existingOrigin.Trim() -ne $RemoteUrl) {
        & git remote set-url origin $RemoteUrl
    }

    # Güvenlik: gizli imzalama/Firebase/admin dosyalarının stage edilmeyeceğinden emin ol
    & git add .
    $stagedSecrets = (& git diff --cached --name-only) | Where-Object {
        $_ -match 'key\.properties$' -or
        $_ -match '\.jks$' -or
        $_ -match '\.keystore$' -or
        $_ -match 'google-services\.json$' -or
        $_ -match 'admin_config\.local\.json$'
    }
    if ($stagedSecrets) {
        throw "Güvenlik engeli: Gizli imzalama dosyası Git'e eklenmeye çalışıldı: $($stagedSecrets -join ', ')"
    }

    & git commit -m "Release v$newVersion (+$newBuildNumber)"
    if ($LASTEXITCODE -ne 0) { throw "git commit başarısız oldu." }

    & git push -u origin main
    if ($LASTEXITCODE -ne 0) { throw "git push başarısız oldu." }

    # 6) GitHub Release oluştur ve imzalı APK'yı yükle
    Write-Step "GitHub Release (v$newVersion) yayınlanıyor..."
    $tagName = "v$newVersion"
    & gh release create $tagName $ApkPath --repo $RepoSlug --title $tagName --notes $Notes
    if ($LASTEXITCODE -ne 0) { throw "gh release create başarısız oldu." }

    Write-Host "`nYayın başarıyla tamamlandı!" -ForegroundColor Green
    Write-Host "Release: https://github.com/$RepoSlug/releases/tag/$tagName"
    Write-Host "version.json: https://raw.githubusercontent.com/$RepoSlug/main/version.json"
}
finally {
    Pop-Location
}
