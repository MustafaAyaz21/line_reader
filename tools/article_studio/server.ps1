param(
    [int]$Port = 48731,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$StudioDir = $PSScriptRoot
$ProjectRoot = (Resolve-Path (Join-Path $StudioDir "..\..")).Path
$ContentDir = Join-Path $ProjectRoot "content"
$ContentArticlesPath = Join-Path $ContentDir "articles.json"
$RootArticlesPath = Join-Path $ProjectRoot "articles.json"
$IndexHtmlPath = Join-Path $StudioDir "index.html"

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Utf8Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8Text([string]$Path, [string]$Text) {
    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Body,
        [string]$ContentType = "application/json; charset=utf-8"
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Send-JsonObject {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [hashtable]$Payload
    )

    $json = $Payload | ConvertTo-Json -Depth 6 -Compress
    Send-Response -Response $Response -StatusCode $StatusCode -Body $json -ContentType "application/json; charset=utf-8"
}

function Read-RequestBody([System.Net.HttpListenerRequest]$Request) {
    $reader = New-Object System.IO.StreamReader($Request.InputStream, [System.Text.Encoding]::UTF8)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Get-ArticlesRawJson {
    if (Test-Path $ContentArticlesPath) {
        return Read-Utf8Text $ContentArticlesPath
    }
    if (Test-Path $RootArticlesPath) {
        return Read-Utf8Text $RootArticlesPath
    }
    return "{`n  `"version`": 1,`n  `"updated_at`": `"$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))`",`n  `"articles`": []`n}`n"
}

function Validate-And-SaveArticles([string]$RawJson) {
    if ([string]::IsNullOrWhiteSpace($RawJson)) {
        throw "Boş JSON verisi kaydedilemez."
    }

    try {
        $parsed = $RawJson | ConvertFrom-Json
    }
    catch {
        throw "Geçersiz JSON biçimi: $($_.Exception.Message)"
    }

    if ($null -eq $parsed -or $null -eq $parsed.PSObject.Properties["articles"]) {
        throw "JSON içinde 'articles' dizisi bulunmalıdır."
    }

    $articleCount = 0
    if ($null -ne $parsed.articles) {
        $articleCount = @($parsed.articles).Count
    }

    $normalized = $RawJson.Replace("`r`n", "`n").TrimEnd() + "`n"
    Write-Utf8Text -Path $ContentArticlesPath -Text $normalized
    Write-Utf8Text -Path $RootArticlesPath -Text $normalized

    return $articleCount
}

function Invoke-GitInRepo([string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.WorkingDirectory = $ProjectRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $escaped = $Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_.Replace('"', '\"')) + '"'
        } else {
            $_
        }
    }
    $psi.Arguments = ($escaped -join ' ')

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return @{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout.Trim()
        StdErr   = $stderr.Trim()
    }
}

function Get-RepoStatus {
    $branchRes = Invoke-GitInRepo @("rev-parse", "--abbrev-ref", "HEAD")
    $remoteRes = Invoke-GitInRepo @("remote", "get-url", "origin")
    $diffRes = Invoke-GitInRepo @("status", "--porcelain", "--", "content/articles.json", "articles.json")

    return @{
        ok                = $true
        branch            = if ($branchRes.ExitCode -eq 0) { $branchRes.StdOut } else { "main" }
        remoteUrl         = if ($remoteRes.ExitCode -eq 0) { $remoteRes.StdOut } else { "" }
        hasPendingPublish = -not [string]::IsNullOrWhiteSpace($diffRes.StdOut)
        contentPath       = $ContentArticlesPath
    }
}

function Publish-ArticlesToGitHub([int]$ArticleCount) {
    $addRes = Invoke-GitInRepo @("add", "--", "content/articles.json", "articles.json")
    if ($addRes.ExitCode -ne 0) {
        throw "git add başarısız: $($addRes.StdErr)"
    }

    $stagedRes = Invoke-GitInRepo @("diff", "--cached", "--name-only", "--", "content/articles.json", "articles.json")
    if ([string]::IsNullOrWhiteSpace($stagedRes.StdOut)) {
        return @{
            ok           = $true
            published    = $false
            articleCount = $ArticleCount
            message      = "Değişiklik yok; tüm makaleler zaten yayında."
        }
    }

    $commitMsg = "Update articles.json ($ArticleCount makale)"
    $commitRes = Invoke-GitInRepo @("commit", "-m", $commitMsg, "--", "content/articles.json", "articles.json")
    if ($commitRes.ExitCode -ne 0) {
        throw "git commit başarısız: $($commitRes.StdErr) $($commitRes.StdOut)"
    }

    $pushRes = Invoke-GitInRepo @("push", "origin", "main")
    if ($pushRes.ExitCode -ne 0) {
        throw "Yerel olarak kaydedildi ancak GitHub'a gönderilemedi (internet veya kimlik doğrulama kontrol edin): $($pushRes.StdErr)"
    }

    $shaRes = Invoke-GitInRepo @("rev-parse", "--short", "HEAD")
    $commitHash = if ($shaRes.ExitCode -eq 0) { $shaRes.StdOut } else { "" }

    return @{
        ok           = $true
        published    = $true
        commit       = $commitHash
        articleCount = $ArticleCount
        message      = "GitHub'a yayınlandı ($commitHash)! Uygulama ve Cloudflare Pages kısa sürede güncellenecek."
    }
}

if (-not (Test-Path $IndexHtmlPath)) {
    throw "Arayüz dosyası bulunamadı: $IndexHtmlPath"
}

$listener = $null
$boundPort = $Port
for ($candidate = $Port; $candidate -le ($Port + 10); $candidate++) {
    $tryListener = New-Object System.Net.HttpListener
    $tryListener.Prefixes.Add("http://127.0.0.1:$candidate/")
    try {
        $tryListener.Start()
        $listener = $tryListener
        $boundPort = $candidate
        break
    }
    catch {
        $tryListener.Close()
    }
}

if ($null -eq $listener) {
    throw "Yerel sunucu için uygun port bulunamadı ($Port..$($Port + 10))."
}

$url = "http://127.0.0.1:$boundPort/"
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Line Reader - Makale Yonetim Paneli" -ForegroundColor White
Write-Host "  Adres : $url" -ForegroundColor Green
Write-Host "  Klasor: $ContentArticlesPath" -ForegroundColor DarkGray
Write-Host "  Kapatmak icin bu pencereyi kapatabilir veya Ctrl+C yapabilirsiniz." -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $NoBrowser) {
    Start-Process $url
}

$running = $true
try {
    while ($running -and $listener.IsListening) {
        try {
            $context = $listener.GetContext()
        }
        catch {
            break
        }

        $req = $context.Request
        $res = $context.Response
        $path = $req.Url.AbsolutePath.ToLowerInvariant()
        $method = $req.HttpMethod.ToUpperInvariant()

        try {
            if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
                $html = Read-Utf8Text $IndexHtmlPath
                Send-Response -Response $res -StatusCode 200 -Body $html -ContentType "text/html; charset=utf-8"
            }
            elseif ($method -eq "GET" -and $path -eq "/api/articles") {
                $rawJson = Get-ArticlesRawJson
                Send-Response -Response $res -StatusCode 200 -Body $rawJson -ContentType "application/json; charset=utf-8"
            }
            elseif ($method -eq "GET" -and $path -eq "/api/status") {
                $status = Get-RepoStatus
                Send-JsonObject -Response $res -StatusCode 200 -Payload $status
            }
            elseif ($method -eq "POST" -and $path -eq "/api/save") {
                $body = Read-RequestBody $req
                $count = Validate-And-SaveArticles $body
                Send-JsonObject -Response $res -StatusCode 200 -Payload @{
                    ok           = $true
                    articleCount = $count
                    message      = "Yerel olarak kaydedildi ($count makale)."
                }
            }
            elseif ($method -eq "POST" -and $path -eq "/api/publish") {
                $body = Read-RequestBody $req
                $count = Validate-And-SaveArticles $body
                $publishResult = Publish-ArticlesToGitHub -ArticleCount $count
                Send-JsonObject -Response $res -StatusCode 200 -Payload $publishResult
            }
            elseif ($method -eq "POST" -and $path -eq "/api/shutdown") {
                Send-JsonObject -Response $res -StatusCode 200 -Payload @{
                    ok      = $true
                    message = "Panel kapatılıyor."
                }
                $running = $false
            }
            else {
                Send-JsonObject -Response $res -StatusCode 404 -Payload @{
                    ok    = $false
                    error = "Bulunamadı: $path"
                }
            }
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Host "[HATA] $method $path -> $errMsg" -ForegroundColor Red
            try {
                Send-JsonObject -Response $res -StatusCode 500 -Payload @{
                    ok    = $false
                    error = $errMsg
                }
            }
            catch {}
        }
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
