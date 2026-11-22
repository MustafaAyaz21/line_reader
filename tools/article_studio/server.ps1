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
$ContentAudioDir = Join-Path $ContentDir "audio"
$RootAudioDir = Join-Path $ProjectRoot "audio"
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
    $diffRes = Invoke-GitInRepo @("status", "--porcelain", "--", "content/articles.json", "articles.json", "content/audio", "audio")

    return @{
        ok                = $true
        branch            = if ($branchRes.ExitCode -eq 0) { $branchRes.StdOut } else { "main" }
        remoteUrl         = if ($remoteRes.ExitCode -eq 0) { $remoteRes.StdOut } else { "" }
        hasPendingPublish = -not [string]::IsNullOrWhiteSpace($diffRes.StdOut)
        contentPath       = $ContentArticlesPath
    }
}

function Publish-ArticlesToGitHub([int]$ArticleCount) {
    $pathsToStage = @("content/articles.json", "articles.json")
    if (Test-Path $ContentAudioDir) { $pathsToStage += "content/audio" }
    if (Test-Path $RootAudioDir) { $pathsToStage += "audio" }

    $addArgs = @("add", "--") + $pathsToStage
    $addRes = Invoke-GitInRepo $addArgs
    if ($addRes.ExitCode -ne 0) {
        throw "git add başarısız: $($addRes.StdErr)"
    }

    $stagedArgs = @("diff", "--cached", "--name-only", "--") + $pathsToStage
    $stagedRes = Invoke-GitInRepo $stagedArgs
    if ([string]::IsNullOrWhiteSpace($stagedRes.StdOut)) {
        return @{
            ok           = $true
            published    = $false
            articleCount = $ArticleCount
            message      = "Değişiklik yok; tüm makaleler ve ses dosyaları zaten yayında."
        }
    }

    $commitMsg = "Update articles and audio ($ArticleCount makale)"
    $commitArgs = @("commit", "-m", $commitMsg, "--") + $pathsToStage
    $commitRes = Invoke-GitInRepo $commitArgs
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
        message      = "GitHub'a yayınlandı ($commitHash)! Makaleler ve podcast sesleri kısa sürede aktif olacak."
    }
}

function Get-AdminConfig {
    $workerUrl = $DefaultWorkerUrl
    $adminSecret = ""
    $geminiApiKey = ""
    $geminiModel = "gemini-2.5-flash-lite"
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
        geminiModel  = if ([string]::IsNullOrWhiteSpace($geminiModel)) { "gemini-2.5-flash-lite" } else { $geminiModel.Trim() }
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
  },
  "paragraph_translations": [
    "Natural, fluent Turkish translation of paragraph 1.",
    "Natural, fluent Turkish translation of paragraph 2."
  ],
  "sentence_translations": {
    "Exact English sentence from content.": "Natural contextual Turkish translation of that exact sentence."
  }
}

Strict requirements:
1. Level: $($levelGuides[$level])
2. Topic: $topicInstruction
3. $avoidBlock
4. Title, description, category, and content MUST all be in natural, well-edited English.
5. Word count of "content" MUST be close to 350 words (320-385 words), split into 4-5 clear paragraphs separated by \n\n. Do NOT include the title inside "content".
6. "word_meanings" MUST contain 35 to 45 important English words or short phrases that ACTUALLY appear verbatim in "content", with lowercase keys and accurate, natural Turkish meanings suited to the exact context of the article (no English explanations, just concise Turkish equivalents).
7. "paragraph_translations" MUST be a JSON array with the exact same number of elements as the paragraphs in "content", providing fluent Turkish translations in order.
8. "sentence_translations" MUST map every sentence of "content" (verbatim English sentence as key) to its fluent, contextual Turkish translation.
9. Output raw JSON only—no markdown fences, no commentary.
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

    $modelsToTry = @(
        $cfg.geminiModel,
        "gemini-2.5-flash-lite",
        "gemini-flash-lite-latest",
        "gemini-2.5-flash",
        "gemini-2.0-flash-lite",
        "gemini-2.0-flash",
        "gemini-flash-latest"
    ) | Select-Object -Unique
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $lastErrorMsg = "Gemini API yanıt vermedi."
    $lastStatus = 502
    $hadTransientOverload = $false

    # Geçici 503 yoğunluklarında önce diğer stabil modellere geç, hepsi yoğun ise 1 kısa bekleme sonrası tekrar dene.
    for ($attemptPass = 1; $attemptPass -le 2; $attemptPass++) {
        $passModels = if ($attemptPass -eq 1) {
            $modelsToTry
        } else {
            if (-not $hadTransientOverload) { break }
            Start-Sleep -Milliseconds 1800
            @("gemini-2.5-flash-lite", "gemini-flash-lite-latest", "gemini-2.5-flash") | Select-Object -Unique
        }

        $abortAll = $false
        foreach ($modelName in $passModels) {
            Write-Host "[Gemini] Deneniyor (tur $attemptPass): $modelName ..." -ForegroundColor DarkCyan
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

                $paraTrList = New-Object System.Collections.ArrayList
                if ($null -ne $articleObj.PSObject.Properties["paragraph_translations"] -and $null -ne $articleObj.paragraph_translations) {
                    foreach ($pt in @($articleObj.paragraph_translations)) {
                        $cleanPt = ([string]$pt).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($cleanPt)) {
                            [void]$paraTrList.Add($cleanPt)
                        }
                    }
                }

                $sentTrOrdered = [ordered]@{}
                if ($null -ne $articleObj.PSObject.Properties["sentence_translations"] -and $null -ne $articleObj.sentence_translations) {
                    foreach ($prop in $articleObj.sentence_translations.PSObject.Properties) {
                        $sk = ([string]$prop.Name).Trim()
                        $sv = ([string]$prop.Value).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($sk) -and -not [string]::IsNullOrWhiteSpace($sv)) {
                            $sentTrOrdered[$sk] = $sv
                        }
                    }
                }

                Write-Host "[Gemini] Basarili: $modelName -> $genTitle" -ForegroundColor Green
                $payload = @{
                    ok      = $true
                    model   = $modelName
                    article = @{
                        level                  = $level
                        title                  = $genTitle
                        description            = $genDesc
                        category               = $genCat
                        author                 = "Line Reader"
                        language               = "en"
                        content                = $genContent
                        word_meanings          = $wmOrdered
                        paragraph_translations = @($paraTrList)
                        sentence_translations  = $sentTrOrdered
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
                    if ($code -eq 503 -or $code -eq 429 -or $code -eq 500) {
                        $hadTransientOverload = $true
                    }
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
                    Write-Host "[Gemini] $modelName -> HTTP $code" -ForegroundColor Yellow

                    # API key geçersizse diğer modelleri denemeye gerek yok
                    if ($code -eq 400 -or $code -eq 401 -or $code -eq 403) {
                        $abortAll = $true
                        break
                    }
                } else {
                    $lastStatus = 502
                    $lastErrorMsg = "Gemini sunucusuna bağlanılamadı: $($_.Exception.Message)"
                    $abortAll = $true
                    break
                }
            }
            catch {
                $lastStatus = 500
                $lastErrorMsg = "Gemini çıktısı işlenemedi ($modelName): $($_.Exception.Message)"
            }
        }
        if ($abortAll) { break }
    }

    if ($lastStatus -eq 503) {
        $lastErrorMsg = "Google Gemini sunucuları şu an geçici olarak çok yoğun (HTTP 503). 5-10 saniye sonra tekrar deneyin veya Gemini Ayarı'ndan 'gemini-2.5-flash-lite' seçin."
    }

    return @{
        StatusCode = $lastStatus
        Body       = (@{ ok = $false; message = $lastErrorMsg } | ConvertTo-Json -Compress)
    }
}

function Convert-PcmToWavBytes([byte[]]$PcmBytes, [int]$SampleRate = 24000) {
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    try {
        $pcmLen = $PcmBytes.Length
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
        $bw.Write([int](36 + $pcmLen))
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
        $bw.Write([int]16)
        $bw.Write([int16]1)
        $bw.Write([int16]1)
        $bw.Write([int]$SampleRate)
        $bw.Write([int]($SampleRate * 2))
        $bw.Write([int16]2)
        $bw.Write([int16]16)
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("data"))
        $bw.Write([int]$pcmLen)
        $bw.Write($PcmBytes)
        $bw.Flush()
        return $ms.ToArray()
    }
    finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

function Convert-WavBytesToM4aBytes([byte[]]$WavBytes) {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
    $asTaskProgress = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncActionWithProgress`1'
    })[0]

    $null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
    $null = [Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType=WindowsRuntime]
    $null = [Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType=WindowsRuntime]
    $null = [Windows.Media.MediaProperties.AudioEncodingQuality, Windows.Media.MediaProperties, ContentType=WindowsRuntime]

    $src = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    $dst = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    try {
        $netSrc = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForWrite($src)
        $netSrc.Write($WavBytes, 0, $WavBytes.Length)
        $netSrc.Flush()
        $src.Seek(0)

        $profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateM4a([Windows.Media.MediaProperties.AudioEncodingQuality]::Medium)
        $transcoder = New-Object Windows.Media.Transcoding.MediaTranscoder
        $prepTask = $asTaskGeneric.MakeGenericMethod([Windows.Media.Transcoding.PrepareTranscodeResult]).Invoke($null, @($transcoder.PrepareStreamTranscodeAsync($src, $dst, $profile)))
        $prepTask.Wait() | Out-Null
        $prep = $prepTask.Result
        if (-not $prep.CanTranscode) {
            throw "Windows AAC kodlayıcı başlatılamadı ($($prep.FailureReason))."
        }

        $runTask = $asTaskProgress.MakeGenericMethod([double]).Invoke($null, @($prep.TranscodeAsync()))
        $runTask.Wait() | Out-Null

        $dst.Seek(0)
        $netDst = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($dst)
        $outMs = New-Object System.IO.MemoryStream
        try {
            $netDst.CopyTo($outMs)
            return $outMs.ToArray()
        }
        finally {
            $outMs.Dispose()
            $netDst.Dispose()
        }
    }
    finally {
        $src.Dispose()
        $dst.Dispose()
    }
}

function Split-ContentIntoSentencesForAudio([string]$Content) {
    $norm = ($Content -replace "`r`n", "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }
    $paragraphs = if ($norm.Contains("`n`n")) {
        [regex]::Split($norm, '\n\s*\n+')
    } else {
        $norm.Split("`n")
    }
    $paragraphs = @($paragraphs | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $abbrevs = @("mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e", "u.s", "u.k")
    $sentences = New-Object System.Collections.ArrayList
    $globalIdx = 0

    for ($pIdx = 0; $pIdx -lt $paragraphs.Count; $pIdx++) {
        $para = $paragraphs[$pIdx]
        $segStart = 0
        $i = 0
        while ($i -lt $para.Length) {
            $ch = $para[$i]
            if ($ch -eq '.' -or $ch -eq '!' -or $ch -eq '?') {
                $skipDot = $false
                if ($ch -eq '.') {
                    if ($i -gt 0 -and ($i + 1) -lt $para.Length -and [char]::IsDigit($para[$i - 1]) -and [char]::IsDigit($para[$i + 1])) {
                        $skipDot = $true
                    } else {
                        $tokStart = $i - 1
                        while ($tokStart -ge 0 -and -not [char]::IsWhiteSpace($para[$tokStart]) -and $para[$tokStart] -ne '(' -and $para[$tokStart] -ne '"') {
                            $tokStart--
                        }
                        $tok = $para.Substring($tokStart + 1, $i - ($tokStart + 1)).ToLowerInvariant()
                        if ($abbrevs -contains $tok -or ($tok.Length -eq 1 -and $tok -match '^[a-z]$')) {
                            $skipDot = $true
                        }
                    }
                }
                if ($skipDot) { $i++; continue }

                $end = $i + 1
                $closingChars = @([char]'.', [char]'!', [char]'?', [char]'"', [char]"'", [char]')', [char]0x201D, [char]0x2019)
                while ($end -lt $para.Length -and ($closingChars -contains $para[$end])) {
                    $end++
                }
                if ($end -ge $para.Length -or [char]::IsWhiteSpace($para[$end])) {
                    $piece = $para.Substring($segStart, $end - $segStart).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($piece)) {
                        [void]$sentences.Add(@{ p = $pIdx; s = $globalIdx; text = $piece })
                        $globalIdx++
                    }
                    $segStart = $end
                    $i = $end
                    continue
                }
            }
            $i++
        }
        if ($segStart -lt $para.Length) {
            $piece = $para.Substring($segStart).Trim()
            if (-not [string]::IsNullOrWhiteSpace($piece)) {
                [void]$sentences.Add(@{ p = $pIdx; s = $globalIdx; text = $piece })
                $globalIdx++
            }
        }
    }
    return @($sentences)
}

function Compute-AudioSentenceSegments([string]$Content, [byte[]]$PcmBytes, [int]$SampleRate = 24000) {
    $sentences = Split-ContentIntoSentencesForAudio $Content
    if ($sentences.Count -eq 0 -or $PcmBytes.Length -lt 480) { return @() }

    $totalSamples = [math]::Floor($PcmBytes.Length / 2)
    $totalMs = [int][math]::Round(($totalSamples * 1000.0) / $SampleRate)
    if ($totalMs -le 0) { return @() }

    # 20ms'lik enerji çerçeveleri oluşturup cümle sınırlarını en yakın duraklamaya oturt.
    $frameMs = 20
    $samplesPerFrame = [int](($SampleRate * $frameMs) / 1000)
    $frameCount = [math]::Floor($totalSamples / $samplesPerFrame)
    $energies = New-Object double[] $frameCount
    for ($f = 0; $f -lt $frameCount; $f++) {
        $baseByte = $f * $samplesPerFrame * 2
        $sum = 0.0
        for ($k = 0; $k -lt $samplesPerFrame; $k += 4) {
            $sample = [BitConverter]::ToInt16($PcmBytes, $baseByte + ($k * 2))
            $sum += [math]::Abs($sample)
        }
        $energies[$f] = $sum
    }

    $totalWeight = 0.0
    $weights = New-Object double[] $sentences.Count
    for ($i = 0; $i -lt $sentences.Count; $i++) {
        $w = [double]$sentences[$i].text.Length + 8.0
        if ($i -gt 0 -and $sentences[$i].p -ne $sentences[$i - 1].p) {
            $w += 14.0
        }
        $weights[$i] = $w
        $totalWeight += $w
    }

    $segments = New-Object System.Collections.ArrayList
    $accWeight = 0.0
    $prevEndMs = 0

    for ($i = 0; $i -lt $sentences.Count; $i++) {
        $startMs = $prevEndMs
        $accWeight += $weights[$i]
        $endMs = if ($i -eq ($sentences.Count - 1)) {
            $totalMs
        } else {
            $expectedMs = [int][math]::Round(($accWeight / $totalWeight) * $totalMs)
            $centerFrame = [int][math]::Floor($expectedMs / $frameMs)
            $winFrames = [int][math]::Floor(1300 / $frameMs)
            $minF = [math]::Max([int][math]::Floor(($startMs + 250) / $frameMs), $centerFrame - $winFrames)
            $maxF = [math]::Min($frameCount - 2, $centerFrame + $winFrames)
            $bestFrame = $centerFrame
            if ($maxF -gt $minF -and $minF -ge 0) {
                $bestScore = [double]::MaxValue
                for ($f = $minF; $f -le $maxF; $f++) {
                    $distPenalty = 1.0 + ([math]::Abs($f - $centerFrame) / [double]($winFrames + 1)) * 0.45
                    $score = ($energies[$f] + $energies[$f + 1]) * $distPenalty
                    if ($score -lt $bestScore) {
                        $bestScore = $score
                        $bestFrame = $f
                    }
                }
            }
            [math]::Max($startMs + 200, [math]::Min($totalMs - 100, $bestFrame * $frameMs))
        }

        [void]$segments.Add([ordered]@{
            p        = [int]$sentences[$i].p
            s        = [int]$sentences[$i].s
            start_ms = [int]$startMs
            end_ms   = [int]$endMs
        })
        $prevEndMs = $endMs
    }

    return @($segments)
}

function Invoke-GeminiGenerateAudio([string]$RawJson) {
    $cfg = Get-AdminConfig
    if ([string]::IsNullOrWhiteSpace($cfg.geminiApiKey)) {
        return @{
            StatusCode = 400
            Body       = (@{ ok = $false; needsKey = $true; message = "Önce Gemini API anahtarınızı girip kaydedin." } | ConvertTo-Json -Compress)
        }
    }

    $reqData = $RawJson | ConvertFrom-Json
    $rawId = if ($reqData.id) { ([string]$reqData.id).Trim() } else { "article-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" }
    $safeId = [regex]::Replace($rawId.ToLowerInvariant(), '[^a-z0-9_-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeId)) { $safeId = "article-audio" }

    $level = if ($reqData.level) { ([string]$reqData.level).Trim().ToUpperInvariant() } else { "B1" }
    $voiceName = if ($reqData.voiceName) { ([string]$reqData.voiceName).Trim() } else { "Kore" }
    $content = if ($reqData.content) { ([string]$reqData.content).Replace("`r`n", "`n").Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($content)) {
        return @{
            StatusCode = 400
            Body       = (@{ ok = $false; message = "Ses üretmek için önce makale içeriği yazın veya oluşturun." } | ConvertTo-Json -Compress)
        }
    }

    $styleHint = if ($level -in @("A1", "A2")) {
        "Read the following English learning article aloud in a warm, friendly, clear, unhurried podcast host voice suited for beginner learners. Pause briefly between sentences and slightly longer between paragraphs. Read ONLY the article text below, without adding any intro or outro:"
    } else {
        "Read the following English article aloud in a warm, natural, engaging human podcast narrator voice with clear articulation, natural rhythm, brief pauses between sentences, and slightly longer pauses between paragraphs. Read ONLY the article text below, without adding any intro or outro:"
    }

    $requestObj = @{
        contents = @(
            @{
                role  = "user"
                parts = @(
                    @{ text = "$styleHint`n`n$content" }
                )
            }
        )
        generationConfig = @{
            responseModalities = @("AUDIO")
            speechConfig       = @{
                voiceConfig = @{
                    prebuiltVoiceConfig = @{
                        voiceName = $voiceName
                    }
                }
            }
        }
    }
    $requestBody = $requestObj | ConvertTo-Json -Depth 10 -Compress

    $ttsModels = @("gemini-2.5-flash-preview-tts", "gemini-2.5-pro-preview-tts")
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $lastErrorMsg = "Gemini podcast sesi üretemedi."
    $lastStatus = 502

    foreach ($modelName in $ttsModels) {
        Write-Host "[Podcast AI] Ses uretiliyor: $modelName ($voiceName) -> $safeId ..." -ForegroundColor Cyan
        $endpoint = "https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=$([System.Uri]::EscapeDataString($cfg.geminiApiKey))"
        $webReq = [System.Net.HttpWebRequest]::Create($endpoint)
        $webReq.Method = "POST"
        $webReq.Timeout = 120000
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
            $base64Audio = ""
            $mimeType = "audio/L16;codec=pcm;rate=24000"
            if ($null -ne $parsedRes.candidates -and $parsedRes.candidates.Count -gt 0) {
                $parts = $parsedRes.candidates[0].content.parts
                foreach ($part in $parts) {
                    if ($null -ne $part.PSObject.Properties["inlineData"] -and $null -ne $part.inlineData -and $part.inlineData.data) {
                        $base64Audio = [string]$part.inlineData.data
                        if ($part.inlineData.mimeType) { $mimeType = [string]$part.inlineData.mimeType }
                        break
                    }
                }
            }

            if ([string]::IsNullOrWhiteSpace($base64Audio)) {
                $lastErrorMsg = "Gemini ses verisi döndürmedi ($modelName)."
                continue
            }

            $rawAudioBytes = [Convert]::FromBase64String($base64Audio)
            $sampleRate = 24000
            if ($mimeType -match 'rate=(\d+)') {
                $sampleRate = [int]$Matches[1]
            }

            $isAlreadyWav = ($rawAudioBytes.Length -ge 12 -and $rawAudioBytes[0] -eq 82 -and $rawAudioBytes[1] -eq 73 -and $rawAudioBytes[2] -eq 70 -and $rawAudioBytes[3] -eq 70)
            $pcmBytes = if ($isAlreadyWav -and $rawAudioBytes.Length -gt 44) {
                $slice = New-Object byte[] ($rawAudioBytes.Length - 44)
                [Array]::Copy($rawAudioBytes, 44, $slice, 0, $slice.Length)
                $slice
            } else {
                $rawAudioBytes
            }
            $wavBytes = if ($isAlreadyWav) { $rawAudioBytes } else { Convert-PcmToWavBytes -PcmBytes $pcmBytes -SampleRate $sampleRate }

            $m4aBytes = Convert-WavBytesToM4aBytes -WavBytes $wavBytes
            $segments = Compute-AudioSentenceSegments -Content $content -PcmBytes $pcmBytes -SampleRate $sampleRate
            $durationMs = [int][math]::Round((($pcmBytes.Length / 2.0) * 1000.0) / $sampleRate)

            if (-not (Test-Path $ContentAudioDir)) { New-Item -ItemType Directory -Path $ContentAudioDir -Force | Out-Null }
            if (-not (Test-Path $RootAudioDir)) { New-Item -ItemType Directory -Path $RootAudioDir -Force | Out-Null }

            $fileName = "$safeId.m4a"
            $contentAudioFile = Join-Path $ContentAudioDir $fileName
            $rootAudioFile = Join-Path $RootAudioDir $fileName
            [System.IO.File]::WriteAllBytes($contentAudioFile, $m4aBytes)
            [System.IO.File]::WriteAllBytes($rootAudioFile, $m4aBytes)

            $sizeKb = [math]::Round($m4aBytes.Length / 1024.0, 1)
            Write-Host "[Podcast AI] Hazir: $fileName ($sizeKb KB, $([math]::Round($durationMs/1000.0, 1)) sn, $($segments.Count) cumle)" -ForegroundColor Green

            $payload = @{
                ok                = $true
                model             = $modelName
                voice             = $voiceName
                file_name         = $fileName
                audio_url         = "https://line-reader.pages.dev/audio/$fileName"
                local_preview_url = "/audio/$fileName"
                duration_ms       = $durationMs
                size_kb           = $sizeKb
                audio_segments    = $segments
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
                try { $errBody = $reader.ReadToEnd() } finally { $reader.Dispose(); $errRes.Close() }
                try {
                    $errJson = $errBody | ConvertFrom-Json
                    $lastErrorMsg = if ($errJson.error -and $errJson.error.message) {
                        "Gemini TTS hatası ($modelName / HTTP $code): $($errJson.error.message)"
                    } else {
                        "Gemini TTS hatası ($modelName / HTTP $code)."
                    }
                } catch {
                    $lastErrorMsg = "Gemini TTS hatası ($modelName / HTTP $code)."
                }
                Write-Host "[Podcast AI] $modelName -> HTTP $code" -ForegroundColor Yellow
                if ($code -eq 400 -or $code -eq 401 -or $code -eq 403) { break }
            } else {
                $lastStatus = 502
                $lastErrorMsg = "Gemini TTS sunucusuna bağlanılamadı: $($_.Exception.Message)"
                break
            }
        }
        catch {
            $lastStatus = 500
            $lastErrorMsg = "Podcast sesi oluşturulamadı: $($_.Exception.Message)"
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
            elseif ($method -eq "POST" -and $path -eq "/api/ai/generate-audio") {
                $body = Read-RequestBody $req
                $audioRes = Invoke-GeminiGenerateAudio $body
                Send-Response -Response $res -StatusCode $audioRes.StatusCode -Body $audioRes.Body -ContentType "application/json; charset=utf-8"
            }
            elseif ($method -eq "GET" -and $path.StartsWith("/audio/")) {
                $rawName = [System.IO.Path]::GetFileName($req.Url.AbsolutePath)
                $safeName = [regex]::Replace($rawName, '[^a-zA-Z0-9._-]', '')
                $targetPath = Join-Path $ContentAudioDir $safeName
                if (-not (Test-Path $targetPath)) {
                    $targetPath = Join-Path $RootAudioDir $safeName
                }
                if (-not [string]::IsNullOrWhiteSpace($safeName) -and (Test-Path $targetPath)) {
                    $bytes = [System.IO.File]::ReadAllBytes($targetPath)
                    $res.StatusCode = 200
                    $res.ContentType = if ($safeName.EndsWith(".mp3")) { "audio/mpeg" } else { "audio/mp4" }
                    $res.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
                    $res.ContentLength64 = $bytes.Length
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                    $res.OutputStream.Close()
                } else {
                    Send-JsonObject -Response $res -StatusCode 404 -Payload @{ ok = $false; error = "Ses dosyası bulunamadı." }
                }
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
