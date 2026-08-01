<#
.SYNOPSIS
    Codex 的视觉：调用火山方舟 Doubao-Seed-2.0-mini 识别图片/截图，把文字/JSON 结果打印到 stdout。
.DESCRIPTION
    支持：单图/多图、截屏、EXIF 方向自动转正、原图坐标裁剪（-Crop）或视图坐标裁剪（-CropView）、
    JSON 输出容错、429/5xx 自动重试、错误原因提示、token 用量与费用统计（可写 CSV 日志）。
.PARAMETER Image
    本地图片路径（单图）。
.PARAMETER Images
    多张图片路径数组（逗号分隔），用于对比分析。
.PARAMETER Screenshot
    截取当前虚拟屏幕（全屏）代替图片。
.PARAMETER FindRecent
    列出最近 N 分钟内常见目录（图片/下载/桌面/文档/临时）里出现的图片文件后退出，用于定位上传的图片。
.PARAMETER RecentMinutes
    -FindRecent 的查找时间窗口，默认 30 分钟。
.PARAMETER Question
    识别/分析要求，默认整体描述。
.PARAMETER Model
    默认 doubao-seed-2-0-mini-260215，可覆盖。
.PARAMETER Detail
    视觉质量档位：low / high / xhigh，默认 high。
.PARAMETER MaxSize
    最长边缩放上限（像素），默认 1280。
.PARAMETER Crop
    裁剪区域（原图坐标），格式 x,y,w,h，用于放大细节。
.PARAMETER CropView
    裁剪区域（模型看到的视图坐标），格式 x,y,w,h；脚本自动换算回原图坐标。
.PARAMETER Json
    要求并校验 JSON 输出；自动剥离 ```json 围栏，解析失败时输出原文。
.PARAMETER LogFile
    用量日志 CSV 路径；默认 C:\Users\<user>\.codex\logs\doubao-vision-usage.csv。
.PARAMETER NoLog
    不写用量日志。
.PARAMETER TimeoutSec
    单次请求超时秒数，默认 600。
.OUTPUTS
    豆包模型的文字回答（-Json 且返回合法 JSON 时为格式化 JSON）。
#>

[CmdletBinding()]
param(
    [string]$Image = '',
    [string[]]$Images = @(),
    [switch]$Screenshot,
    [switch]$FindRecent,
    [int]$RecentMinutes = 30,
    [string]$Question = '请仔细分析这张图片，描述关键内容与质量特征。',
    [string]$Model = 'doubao-seed-2-0-mini-260215',
    [ValidateSet('low', 'high', 'xhigh')]
    [string]$Detail = 'high',
    [int]$MaxSize = 1280,
    [string]$Crop = '',
    [string]$CropView = '',
    [switch]$Json,
    [string]$LogFile = '',
    [switch]$NoLog,
    [int]$TimeoutSec = 600
)

$ErrorActionPreference = 'Stop'

# 兼容 "-Images a.jpg,b.jpg" 的逗号分隔写法
if ($Images) {
    $Images = @($Images | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Write-Info {
    Write-Host $args -ForegroundColor DarkGray
}

function Get-ExifOrientation {
    param([System.Drawing.Image]$Img)
    try {
        foreach ($prop in $Img.PropertyItems) {
            if ($prop.Id -eq 0x0112 -and $prop.Type -eq 3 -and $prop.Len -ge 2) {
                $val = [BitConverter]::ToUInt16($prop.Value, 0)
                switch ($val) {
                    2 { return [System.Drawing.RotateFlipType]::RotateNoneFlipX }
                    3 { return [System.Drawing.RotateFlipType]::Rotate180FlipNone }
                    4 { return [System.Drawing.RotateFlipType]::RotateNoneFlipY }
                    5 { return [System.Drawing.RotateFlipType]::Rotate90FlipX }
                    6 { return [System.Drawing.RotateFlipType]::Rotate90FlipNone }
                    7 { return [System.Drawing.RotateFlipType]::Rotate270FlipX }
                    8 { return [System.Drawing.RotateFlipType]::Rotate270FlipNone }
                }
            }
        }
    }
    catch { }
    return $null
}

function ConvertTo-ImageBase64 {
    param(
        [string]$Path,
        [int]$MaxSizePx,
        [string]$CropSpec,
        [string]$CropViewSpec
    )
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile($Path)
    try {
        # EXIF 方向转正
        $rot = Get-ExifOrientation -Img $src
        if ($rot) {
            $work = New-Object System.Drawing.Bitmap($src)
            $work.RotateFlip($rot)
            $src.Dispose()
            $src = $work
        }

        $x = 0; $y = 0; $w = $src.Width; $h = $src.Height
        $scale = [Math]::Min(1.0, $MaxSizePx / [Math]::Max($w, $h))

        if ($CropSpec -and $CropViewSpec) { throw '-Crop 与 -CropView 不能同时使用' }
        if ($CropSpec -or $CropViewSpec) {
            $spec = if ($CropSpec) { $CropSpec } else { $CropViewSpec }
            $parts = $spec -split ',' | ForEach-Object { [int]($_.Trim()) }
            if ($parts.Count -ne 4) { throw '裁剪格式应为 x,y,w,h' }
            $cx = $parts[0]; $cy = $parts[1]; $cw = $parts[2]; $ch = $parts[3]
            if ($CropViewSpec) {
                # 视图坐标 → 原图坐标
                $cx = [int][Math]::Round($cx / $scale)
                $cy = [int][Math]::Round($cy / $scale)
                $cw = [int][Math]::Round($cw / $scale)
                $ch = [int][Math]::Round($ch / $scale)
            }
            if ($cx -lt 0 -or $cy -lt 0 -or $cw -le 0 -or $ch -le 0 -or
                ($cx + $cw) -gt $src.Width -or ($cy + $ch) -gt $src.Height) {
                throw "裁剪超出图片范围：x=$cx y=$cy w=$cw h=$ch（原图 $($src.Width)x$($src.Height)）"
            }
            $x = $cx; $y = $cy; $w = $cw; $h = $ch
            $scale = [Math]::Min(1.0, $MaxSizePx / [Math]::Max($w, $h))
        }

        $nw = [int][Math]::Max(1, [Math]::Round($w * $scale))
        $nh = [int][Math]::Max(1, [Math]::Round($h * $scale))
        $bmp = New-Object System.Drawing.Bitmap($nw, $nh)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $srcRect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
            $dstRect = New-Object System.Drawing.Rectangle(0, 0, $nw, $nh)
            $g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        }
        finally { $g.Dispose() }
        $ms = New-Object System.IO.MemoryStream
        try {
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            return [PSCustomObject]@{
                Base64 = [Convert]::ToBase64String($ms.ToArray())
                ViewWidth = $nw
                ViewHeight = $nh
            }
        }
        finally { $ms.Dispose(); $bmp.Dispose() }
    }
    finally { $src.Dispose() }
}

function Find-RecentImages {
    param([int]$Minutes)
    $cutoff = (Get-Date).AddMinutes(-$Minutes)
    $roots = @(
        (Join-Path $HOME 'Pictures'),
        (Join-Path $HOME 'Downloads'),
        (Join-Path $HOME 'Desktop'),
        (Join-Path $HOME 'Documents'),
        $env:TEMP
    ) | Where-Object { $_ -and (Test-Path $_) }
    $exts = @('*.jpg', '*.jpeg', '*.png', '*.webp', '*.bmp', '*.tif', '*.tiff', '*.heic')
    $hits = foreach ($root in $roots) {
        foreach ($ext in $exts) {
            Get-ChildItem -Path $root -Filter $ext -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $cutoff }
        }
    }
    $hits | Sort-Object LastWriteTime -Descending | Select-Object -First 20 | ForEach-Object {
        "[{0}] {1}" -f $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $_.FullName
    }
}

function Invoke-ArkWithRetry {
    param(
        [hashtable]$Body,
        [hashtable]$Headers,
        [int]$TimeoutSec,
        [int]$MaxRetries = 2
    )
    $attempt = 0
    while ($attempt -le $MaxRetries) {
        try {
            return Invoke-RestMethod -Uri 'https://ark.cn-beijing.volces.com/api/v3/chat/completions' -Method Post `
                -Headers $Headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 12) -TimeoutSec $TimeoutSec
        }
        catch {
            $status = $null
            $errCode = ''
            $errMsg = ''
            if ($_.Exception.Response) {
                try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            }
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try {
                    $err = $_.ErrorDetails.Message | ConvertFrom-Json
                    if ($err.error) {
                        $errCode = [string]$err.error.code
                        $errMsg = [string]$err.error.message
                    }
                    elseif ($err.code) {
                        $errCode = [string]$err.code
                        $errMsg = [string]$err.message
                    }
                    else { $errMsg = $_.ErrorDetails.Message }
                }
                catch { $errMsg = $_.ErrorDetails.Message }
            }
            if (-not $errMsg) { $errMsg = $_.Exception.Message }

            $retryable = ($null -eq $status) -or ($status -eq 429) -or ($status -ge 500 -and $status -le 599)
            if ($retryable -and $attempt -lt $MaxRetries) {
                $attempt++
                Start-Sleep -Seconds (2 * $attempt)
                continue
            }

            $hint = switch ($status) {
                401 { 'API Key 无效或未授权，请检查 ARK_API_KEY 环境变量' }
                403 { '无权限或账户余额不足，请到火山方舟控制台检查' }
                404 { "模型不存在或未开通，请确认方舟控制台已开通：$($Body.model)" }
                429 { '请求过于频繁（限流），重试后仍失败，请稍后再试' }
                default { '火山方舟调用失败' }
            }
            if ($errCode) { $hint += "（错误码 $errCode）" }
            if ($errMsg) { $hint += "：$errMsg" }
            throw $hint
        }
    }
}

function ConvertTo-ParsedJson {
    param([string]$Text)
    $t = $Text.Trim()
    $t = [regex]::Replace($t, '^\s*```(?:json)?\s*', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $t = [regex]::Replace($t, '\s*```\s*$', '')
    try { return $t | ConvertFrom-Json }
    catch {
        $m = [regex]::Match($t, '(?s)\{.*\}')
        if ($m.Success) { return $m.Value | ConvertFrom-Json }
        throw
    }
}

# ---------- 0. 查找最近上传的图片 ----------
if ($FindRecent) {
    $result = Find-RecentImages -Minutes $RecentMinutes
    if (-not $result) { Write-Output ('最近 ' + $RecentMinutes + ' 分钟内未在常见目录找到图片') }
    else { $result }
    exit 0
}

# ---------- 1. 获取图像 ----------
$imageList = @()
if ($Screenshot) {
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size) }
    finally { $g.Dispose() }
    $shotPath = Join-Path $env:TEMP ("doubao-vision-shot-" + [guid]::NewGuid().ToString('N') + '.png')
    $bmp.Save($shotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Info "截图已保存: $shotPath"
    $imageList += $shotPath
}
if ($Image) { $imageList += $Image }
if ($Images) { $imageList += $Images }
$imageList = @($imageList | Select-Object -Unique)

if ($imageList.Count -eq 0) { throw '必须提供 -Image / -Images、-Screenshot，或先用 -FindRecent 查找上传的图片' }
if ($imageList.Count -gt 1 -and ($Crop -or $CropView)) { throw '多图模式（-Images）不支持裁剪（-Crop / -CropView）' }

$resolved = @()
foreach ($p in $imageList) {
    if (-not (Test-Path -LiteralPath $p)) { throw "图片不存在: $p" }
    $resolved += (Resolve-Path -LiteralPath $p).Path
}
$imageList = $resolved

# ---------- 2. 检查密钥 ----------
if (-not $env:ARK_API_KEY) {
    throw '未设置 ARK_API_KEY：请在火山方舟控制台创建 API Key 并设置环境变量'
}

# ---------- 3. 编码图片 ----------
Write-Info "Model: $Model | Detail: $Detail"
$contentParts = @(@{ type = 'text'; text = $Question })
foreach ($imgPath in $imageList) {
    Write-Info "Image: $imgPath"
    $enc = ConvertTo-ImageBase64 -Path $imgPath -MaxSizePx $MaxSize -CropSpec $Crop -CropViewSpec $CropView
    Write-Info "视图尺寸: $($enc.ViewWidth) x $($enc.ViewHeight)"
    $contentParts += @{ type = 'image_url'; image_url = @{ url = ('data:image/png;base64,' + $enc.Base64); detail = $Detail } }
}

$bodyObj = @{
    model    = $Model
    messages = @(@{ role = 'user'; content = $contentParts })
}
$headers = @{ Authorization = 'Bearer ' + $env:ARK_API_KEY }

# ---------- 4. 调用豆包（自动重试 + 错误原因提示） ----------
$resp = Invoke-ArkWithRetry -Body $bodyObj -Headers $headers -TimeoutSec $TimeoutSec
$text = [string]$resp.choices[0].message.content

# ---------- 5. 用量统计与日志（豆包 mini：输入 0.2 元/百万，输出 2 元/百万，缓存命中 0.04 元/百万） ----------
try {
    $usage = $resp.usage
    if ($usage) {
        $pTok = [int]$usage.prompt_tokens
        $cTok = [int]$usage.completion_tokens
        $cached = 0
        if ($usage.prompt_tokens_details -and $usage.prompt_tokens_details.cached_tokens) {
            $cached = [int]$usage.prompt_tokens_details.cached_tokens
        }
        $cost = ($pTok - $cached) * 0.2 / 1e6 + $cached * 0.04 / 1e6 + $cTok * 2 / 1e6
        Write-Info (("用量: 输入 {0} tokens（缓存 {1}）| 输出 {2} tokens | 估算费用 ¥{3:N5}") -f $pTok, $cached, $cTok, $cost)

        if (-not $NoLog) {
            $logPath = if ($LogFile) { $LogFile } else { Join-Path $HOME '.codex\logs\doubao-vision-usage.csv' }
            try {
                $logDir = Split-Path $logPath -Parent
                if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
                $q = if ($Question.Length -gt 80) { $Question.Substring(0, 80) } else { $Question }
                [PSCustomObject]@{
                    Timestamp        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    Model            = $Model
                    Detail           = $Detail
                    Images           = ($imageList -join '; ')
                    PromptTokens     = $pTok
                    CachedTokens     = $cached
                    CompletionTokens = $cTok
                    TotalTokens      = $pTok + $cTok
                    CostYuan         = [math]::Round($cost, 6)
                    Question         = $q
                } | Export-Csv -Path $logPath -Append -NoTypeInformation -Encoding UTF8
                Write-Info "用量日志: $logPath"
            }
            catch { Write-Info ("用量日志写入失败: " + $_.Exception.Message) }
        }
    }
}
catch { }

# ---------- 6. 输出 ----------
if ($Json) {
    try {
        $parsed = ConvertTo-ParsedJson -Text $text
        $parsed | ConvertTo-Json -Depth 8
    }
    catch {
        Write-Info '模型未返回合法 JSON，输出原文：'
        $text
    }
}
else {
    $text
}
