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
$AdminConfigPath = Join-Path $StudioDir "admin_config.local.json"
$DefaultWorkerUrl = "https://linereader-ai.xreasayaz21.workers.dev"

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

function Get-AdminConfig {
    $workerUrl = $DefaultWorkerUrl
    $adminSecret = ""
    $geminiApiKey = ""
    $geminiModel = "gemini-2.5-flash"
    if (Test-Path $AdminConfigPath) {
        try {
            $parsed = (Read-Utf8Text $AdminConfigPath) | ConvertFrom-Json
            if ($parsed.workerUrl) { $workerUrl = [string]$parsed.workerUrl }
            if ($parsed.adminSecret) { $adminSecret = [string]$parsed.adminSecret }
            if ($parsed.geminiApiKey) { $geminiApiKey = [string]$parsed.geminiApiKey }
            if ($parsed.geminiModel) { $geminiModel = [string]$parsed.geminiModel }
        }
        catch {}
    }
    return @{
        workerUrl    = $workerUrl.Trim().TrimEnd("/")
        adminSecret  = $adminSecret.Trim()
        geminiApiKey = $geminiApiKey.Trim()
        geminiModel  = if ([string]::IsNullOrWhiteSpace($geminiModel)) { "gemini-2.5-flash" } else { $geminiModel.Trim() }
    }
}

function Write-LocalAdminConfig([hashtable]$Cfg) {
    $obj = [ordered]@{
        workerUrl    = $Cfg.workerUrl
        adminSecret  = $Cfg.adminSecret
        geminiApiKey = $Cfg.geminiApiKey
        geminiModel  = $Cfg.geminiModel
    }
    Write-Utf8Text -Path $AdminConfigPath -Text (($obj | ConvertTo-Json -Depth 3) + "`n")
}

function Save-AdminConfig([string]$RawJson) {
    $parsed = $RawJson | ConvertFrom-Json
    $current = Get-AdminConfig
    $nextUrl = if ($parsed.workerUrl) { ([string]$parsed.workerUrl).Trim().TrimEnd("/") } else { $current.workerUrl }
    $nextSecret = if ($null -ne $parsed.PSObject.Properties["adminSecret"] -and -not [string]::IsNullOrWhiteSpace([string]$parsed.adminSecret)) {
        ([string]$parsed.adminSecret).Trim()
    } else {
        $current.adminSecret
    }

    $current.workerUrl = $nextUrl
    $current.adminSecret = $nextSecret
    Write-LocalAdminConfig $current

    return @{
        ok        = $true
        workerUrl = $nextUrl
        hasSecret = -not [string]::IsNullOrWhiteSpace($nextSecret)
        message   = "Yönetici bağlantısı yerel olarak kaydedildi."
    }
}

function Save-AiConfig([string]$RawJson) {
    $parsed = $RawJson | ConvertFrom-Json
    $current = Get-AdminConfig
    if ($null -ne $parsed.PSObject.Properties["geminiApiKey"] -and -not [string]::IsNullOrWhiteSpace([string]$parsed.geminiApiKey)) {
        $current.geminiApiKey = ([string]$parsed.geminiApiKey).Trim()
    }
    if ($null -ne $parsed.PSObject.Properties["geminiModel"] -and -not [string]::IsNullOrWhiteSpace([string]$parsed.geminiModel)) {
        $current.geminiModel = ([string]$parsed.geminiModel).Trim()
    }
    Write-LocalAdminConfig $current

    return @{
        ok           = $true
        hasGeminiKey = -not [string]::IsNullOrWhiteSpace($current.geminiApiKey)
        geminiModel  = $current.geminiModel
        message      = "Gemini API ayarı yerel olarak kaydedildi."
    }
}

function Invoke-GeminiGenerateArticle([string]$RawJson) {
    $cfg = Get-AdminConfig
    if ([string]::IsNullOrWhiteSpace($cfg.geminiApiKey)) {
        return @{
            StatusCode = 400
            Body       = (@{ ok = $false; needsKey = $true; message = "Önce Gemini API anahtarınızı girip kaydedin." } | ConvertTo-Json -Compress)
        }
    }

    $reqData = @{}
    if (-not [string]::IsNullOrWhiteSpace($RawJson)) {
        $reqData = $RawJson | ConvertFrom-Json
    }

    $level = "B1"
    if ($null -ne $reqData -and $null -ne $reqData.PSObject.Properties["level"] -and -not [string]::IsNullOrWhiteSpace([string]$reqData.level)) {
        $candidateLvl = ([string]$reqData.level).Trim().ToUpperInvariant()
        if ($candidateLvl -in @("A1", "A2", "B1", "B2", "C1", "C2")) {
            $level = $candidateLvl
        }
    }

    $topic = ""
    if ($null -ne $reqData -and $null -ne $reqData.PSObject.Properties["topic"]) {
        $topic = ([string]$reqData.topic).Trim()
    }

    $avoidTitles = @()
    if ($null -ne $reqData -and $null -ne $reqData.PSObject.Properties["existingTitles"] -and $null -ne $reqData.existingTitles) {
        $avoidTitles = @($reqData.existingTitles | Select-Object -First 40)
    }

    $levelGuides = @{
        "A1" = "CEFR A1 (Beginner): Very simple short sentences, high-frequency everyday vocabulary, present simple / past simple tenses, clear and easy to follow."
        "A2" = "CEFR A2 (Elementary): Straightforward connected sentences, everyday topics, basic linking words (because, however, when), practical vocabulary."
        "B1" = "CEFR B1 (Intermediate): Natural engaging prose, clear paragraph flow, moderate idiomatic expressions, varied tenses and everyday-to-general vocabulary."
        "B2" = "CEFR B2 (Upper Intermediate): Well-developed arguments and vivid details, richer collocations, nuanced transitions, articulate journalistic/essay style."
        "C1" = "CEFR C1 (Advanced): Sophisticated vocabulary, complex sentence structures, subtle ideas, compelling magazine-quality essay prose."
        "C2" = "CEFR C2 (Proficiency): Literary or scholarly elegance, precise idioms, rich stylistic variety, deep intellectual engagement."
    }

    $randomSeedDomains = @(
        "everyday science & surprising natural phenomena",
        "human psychology & habits",
        "world history & forgotten stories",
        "architecture & urban design",
        "food culture & culinary traditions",
        "technology & the future of work",
        "music, art & creative thinking",
        "travel, geography & hidden places",
        "oceans, wildlife & ecosystems",
        "space exploration & astronomy",
        "language, communication & memory",
        "sports, endurance & human performance",
        "economics, trade & how everyday objects are made",
        "sleep, health & modern lifestyle"
    )
    $suggestedDomain = $randomSeedDomains[(Get-Random -Minimum 0 -Maximum $randomSeedDomains.Count)]

    $topicInstruction = if (-not [string]::IsNullOrWhiteSpace($topic)) {
        "Write specifically about this topic: `"$topic`"."
    } else {
        "Choose an original, fascinating, specific angle within or inspired by: $suggestedDomain (pick a fresh, concrete topic—not generic)."
    }

    $avoidBlock = if ($avoidTitles.Count -gt 0) {
        "Do NOT repeat or closely imitate any of these existing article titles: " + ($avoidTitles -join "; ") + "."
    } else {
        ""
    }

    $prompt = @"
You are a senior English reading editor for the Line Reader language-learning app.
Create ONE original English reading article and return ONLY a valid JSON object matching this exact schema:
{
  "title": "Engaging English title (4-9 words)",
  "description": "Concise English summary for the article card (1-2 sentences, 18-32 words).",
  "category": "Single clear English category (e.g. Science, History, Culture, Psychology, Technology, Nature, Travel, Society, Health, Daily Life)",
  "content": "Full English article text with 4 to 5 well-structured paragraphs separated by double newlines (\n\n). Target length: approximately 350 words (strictly between 320 and 385 words).",
  "word_meanings": {
    "example_word": "contextual Turkish meaning (concise, 1-5 Turkish words)"
  }
}

Strict requirements:
1. Level: $($levelGuides[$level])
2. Topic: $topicInstruction
3. $avoidBlock
4. Title, description, category, and content MUST all be in natural, well-edited English.
5. Word count of "content" MUST be close to 350 words (320-385 words), split into 4-5 clear paragraphs separated by \n\n. Do NOT include the title inside "content".
6. "word_meanings" MUST contain 35 to 45 important English words or short phrases that ACTUALLY appear verbatim in "content", with lowercase keys and accurate, natural Turkish meanings suited to the exact context of the article (no English explanations, just concise Turkish equivalents).
7. Output raw JSON only—no markdown fences, no commentary.
"@

    $requestObj = @{
        contents = @(
            @{
                role  = "user"
                parts = @(
                    @{ text = $prompt }
                )
            }
        )
        generationConfig = @{
            temperature      = 0.9
            responseMimeType = "application/json"
        }
    }
    $requestBody = $requestObj | ConvertTo-Json -Depth 8 -Compress

    $modelsToTry = @($cfg.geminiModel, "gemini-2.5-flash", "gemini-2.0-flash", "gemini-flash-latest") | Select-Object -Unique
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $lastErrorMsg = "Gemini API yanıt vermedi."
    $lastStatus = 502

    foreach ($modelName in $modelsToTry) {
        $endpoint = "https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=$([System.Uri]::EscapeDataString($cfg.geminiApiKey))"
        $webReq = [System.Net.HttpWebRequest]::Create($endpoint)
        $webReq.Method = "POST"
        $webReq.Timeout = 60000
        $webReq.Accept = "application/json"
        $webReq.ContentType = "application/json; charset=utf-8"

        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($requestBody)
        $webReq.ContentLength = $bodyBytes.Length
        $reqStream = $webReq.GetRequestStream()
        try {
            $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        }
        finally {
            $reqStream.Dispose()
        }

        try {
            $webRes = $webReq.GetResponse()
            $reader = New-Object System.IO.StreamReader($webRes.GetResponseStream(), [System.Text.Encoding]::UTF8)
            try {
                $resText = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
                $webRes.Close()
            }

            $parsedRes = $resText | ConvertFrom-Json
            $rawModelText = ""
            if ($null -ne $parsedRes.candidates -and $parsedRes.candidates.Count -gt 0) {
                $parts = $parsedRes.candidates[0].content.parts
                if ($null -ne $parts -and $parts.Count -gt 0) {
                    $rawModelText = [string]$parts[0].text
                }
            }

            if ([string]::IsNullOrWhiteSpace($rawModelText)) {
                $lastErrorMsg = "Gemini boş yanıt döndürdü ($modelName)."
                continue
            }

            $cleanedJson = $rawModelText.Trim()
            if ($cleanedJson -match '(?s)^```(?:json)?\s*(.*?)\s*```$') {
                $cleanedJson = $Matches[1].Trim()
            }
            $firstBrace = $cleanedJson.IndexOf('{')
            $lastBrace = $cleanedJson.LastIndexOf('}')
            if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
                $cleanedJson = $cleanedJson.Substring($firstBrace, $lastBrace - $firstBrace + 1)
            }

            $articleObj = $cleanedJson | ConvertFrom-Json
            $genTitle = if ($articleObj.title) { ([string]$articleObj.title).Trim() } else { "" }
            $genDesc = if ($articleObj.description) { ([string]$articleObj.description).Trim() } else { "" }
            $genCat = if ($articleObj.category) { ([string]$articleObj.category).Trim() } else { "General" }
            $genContent = if ($articleObj.content) { ([string]$articleObj.content).Replace("`r`n", "`n").Trim() } else { "" }

            if ([string]::IsNullOrWhiteSpace($genTitle) -or [string]::IsNullOrWhiteSpace($genContent)) {
                $lastErrorMsg = "Gemini çıktısında başlık veya içerik eksikti ($modelName)."
                continue
            }

            $wmOrdered = [ordered]@{}
            if ($null -ne $articleObj.PSObject.Properties["word_meanings"] -and $null -ne $articleObj.word_meanings) {
                foreach ($prop in $articleObj.word_meanings.PSObject.Properties) {
                    $k = ([string]$prop.Name).Trim().ToLowerInvariant()
                    $v = ([string]$prop.Value).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($k) -and -not [string]::IsNullOrWhiteSpace($v)) {
                        $wmOrdered[$k] = $v
                    }
                }
            }

            $payload = @{
                ok      = $true
                model   = $modelName
                article = @{
                    level         = $level
                    title         = $genTitle
                    description   = $genDesc
                    category      = $genCat
                    author        = "Line Reader"
                    language      = "en"
                    content       = $genContent
                    word_meanings = $wmOrdered
                }
            }
            return @{
                StatusCode = 200
                Body       = ($payload | ConvertTo-Json -Depth 8 -Compress)
            }
        }
        catch [System.Net.WebException] {
            $errRes = $_.Exception.Response
            if ($null -ne $errRes) {
                $code = [int]$errRes.StatusCode
                $lastStatus = $code
                $reader = New-Object System.IO.StreamReader($errRes.GetResponseStream(), [System.Text.Encoding]::UTF8)
                try {
                    $errBody = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                    $errRes.Close()
                }
                try {
                    $errJson = $errBody | ConvertFrom-Json
                    if ($errJson.error -and $errJson.error.message) {
                        $lastErrorMsg = "Gemini hatası ($modelName / HTTP $code): $($errJson.error.message)"
                    } else {
                        $lastErrorMsg = "Gemini hatası ($modelName / HTTP $code)."
                    }
                }
                catch {
                    $lastErrorMsg = "Gemini hatası ($modelName / HTTP $code)."
                }

                # API key geçersizse diğer modelleri denemeye gerek yok
                if ($code -eq 400 -or $code -eq 401 -or $code -eq 403) {
                    break
                }
            } else {
                $lastStatus = 502
                $lastErrorMsg = "Gemini sunucusuna bağlanılamadı: $($_.Exception.Message)"
                break
            }
        }
        catch {
            $lastStatus = 500
            $lastErrorMsg = "Gemini çıktısı işlenemedi ($modelName): $($_.Exception.Message)"
        }
    }

    return @{
        StatusCode = $lastStatus
        Body       = (@{ ok = $false; message = $lastErrorMsg } | ConvertTo-Json -Compress)
    }
}

function Forward-WorkerAdminRequest {
    param(
        [string]$RemotePath,
        [string]$HttpMethod,
        [string]$BodyText = ""
    )

    $cfg = Get-AdminConfig
    if ([string]::IsNullOrWhiteSpace($cfg.adminSecret)) {
        return @{
            StatusCode = 400
            Body       = (@{ ok = $false; message = "Önce yukarıdan Yönetici Şifresi (ADMIN_SECRET) girip kaydedin." } | ConvertTo-Json -Compress)
        }
    }

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $targetUrl = "$($cfg.workerUrl)$RemotePath"
    $webReq = [System.Net.HttpWebRequest]::Create($targetUrl)
    $webReq.Method = $HttpMethod
    $webReq.Timeout = 15000
    $webReq.Accept = "application/json"
    $webReq.Headers.Add("X-Admin-Secret", $cfg.adminSecret)

    if ($HttpMethod -ne "GET" -and -not [string]::IsNullOrWhiteSpace($BodyText)) {
        $webReq.ContentType = "application/json; charset=utf-8"
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($BodyText)
        $webReq.ContentLength = $bodyBytes.Length
        $reqStream = $webReq.GetRequestStream()
        try {
            $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        }
        finally {
            $reqStream.Dispose()
        }
    }

    try {
        $webRes = $webReq.GetResponse()
        $reader = New-Object System.IO.StreamReader($webRes.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try {
            $resBody = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $webRes.Close()
        }
        return @{
            StatusCode = [int]$webRes.StatusCode
            Body       = $resBody
        }
    }
    catch [System.Net.WebException] {
        $errRes = $_.Exception.Response
        if ($null -ne $errRes) {
            $reader = New-Object System.IO.StreamReader($errRes.GetResponseStream(), [System.Text.Encoding]::UTF8)
            try {
                $errBody = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
                $errRes.Close()
            }
            return @{
                StatusCode = [int]$errRes.StatusCode
                Body       = $errBody
            }
        }
        return @{
            StatusCode = 502
            Body       = (@{ ok = $false; message = "Cloudflare Worker sunucusuna ulaşılamadı: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
        }
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
            elseif ($method -eq "GET" -and $path -eq "/api/admin/config") {
                $cfg = Get-AdminConfig
                Send-JsonObject -Response $res -StatusCode 200 -Payload @{
                    ok        = $true
                    workerUrl = $cfg.workerUrl
                    hasSecret = -not [string]::IsNullOrWhiteSpace($cfg.adminSecret)
                }
            }
            elseif ($method -eq "POST" -and $path -eq "/api/admin/config") {
                $body = Read-RequestBody $req
                $savedCfg = Save-AdminConfig $body
                Send-JsonObject -Response $res -StatusCode 200 -Payload $savedCfg
            }
            elseif ($path -eq "/api/admin/codes" -and ($method -in @("GET", "POST", "PATCH", "DELETE"))) {
                $body = if ($method -eq "GET") { "" } else { Read-RequestBody $req }
                $fwd = Forward-WorkerAdminRequest -RemotePath "/admin/codes" -HttpMethod $method -BodyText $body
                Send-Response -Response $res -StatusCode $fwd.StatusCode -Body $fwd.Body -ContentType "application/json; charset=utf-8"
            }
            elseif ($path -eq "/api/admin/users" -and ($method -in @("GET", "POST", "DELETE"))) {
                $body = if ($method -eq "GET") { "" } else { Read-RequestBody $req }
                $fwd = Forward-WorkerAdminRequest -RemotePath "/admin/users" -HttpMethod $method -BodyText $body
                Send-Response -Response $res -StatusCode $fwd.StatusCode -Body $fwd.Body -ContentType "application/json; charset=utf-8"
            }
            elseif ($method -eq "GET" -and $path -eq "/api/ai/config") {
                $cfg = Get-AdminConfig
                Send-JsonObject -Response $res -StatusCode 200 -Payload @{
                    ok           = $true
                    hasGeminiKey = -not [string]::IsNullOrWhiteSpace($cfg.geminiApiKey)
                    geminiModel  = $cfg.geminiModel
                }
            }
            elseif ($method -eq "POST" -and $path -eq "/api/ai/config") {
                $body = Read-RequestBody $req
                $savedAi = Save-AiConfig $body
                Send-JsonObject -Response $res -StatusCode 200 -Payload $savedAi
            }
            elseif ($method -eq "POST" -and $path -eq "/api/ai/generate-article") {
                $body = Read-RequestBody $req
                $genRes = Invoke-GeminiGenerateArticle $body
                Send-Response -Response $res -StatusCode $genRes.StatusCode -Body $genRes.Body -ContentType "application/json; charset=utf-8"
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
