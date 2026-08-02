<#
.SYNOPSIS
    Codex 的声音：调用豆包语音合成 2.0（seed-tts-2.0）把文本合成为语音，保存并可选播放。
.DESCRIPTION
    使用 HTTP 分块流式接口：
      POST https://openspeech.bytedance.com/api/v3/tts/unidirectional
    鉴权头：X-Api-Key、X-Api-App-Id、X-Api-Resource-Id: seed-tts-2.0
    响应为换行分隔 JSON（NDJSON），每行的 data 字段是 base64 音频分片。

    默认请求 pcm 裸流并本地补写 WAV 头，用 System.Media.SoundPlayer 直接播放，
    无需安装 ffmpeg。也支持 mp3 / ogg_opus / wav / m4a / aac 纯保存。
.PARAMETER Text
    要朗读的文本。
.PARAMETER TextFile
    从 UTF-8 文件读取文本（与 -Text 二选一）。
.PARAMETER Speaker
    音色 ID，默认 zh_female_vv_uranus_bigtts（vivi 2.0，对应 seed-tts-2.0 资源）。
.PARAMETER Format
    输出格式：pcm（默认，自动包装为 wav）/ wav / mp3 / ogg_opus / m4a / aac。
.PARAMETER SampleRate
    采样率，默认 24000（支持 8000/16000/22050/24000/32000/44100/48000）。
.PARAMETER OutFile
    输出音频文件路径；默认保存到 ~/.codex/logs/doubao-voice/tts-<时间戳>.wav。
.PARAMETER Play
    合成后立即播放（仅 pcm/wav 支持，无 ffmpeg 依赖）。
.PARAMETER NoSave
    不保存音频文件（需配合 -Play 使用，播放后临时文件自动清理）。
.PARAMETER SpeechRate
    语速，范围 -50..100（100 为 2 倍速，-50 为 0.5 倍速）。
.PARAMETER Emotion
    情感参数（如 happy / sad / angry，视音色支持情况）。
.PARAMETER Language
    显式语言：zh-cn / en / ja / es-mx / id / pt-br / ko。
.PARAMETER CleanMarkdown
    开启 markdown 过滤：**加粗** 会按“加粗”朗读，适合朗读 Codex 回复。
.PARAMETER ListSpeakers
    打印内置常用音色后退出。
.PARAMETER BaseUrl
    接口域名覆盖；默认 https://openspeech.bytedance.com
    （BytePlus 国际站可设为 https://voice.ap-southeast-1.bytepluses.com）。
.PARAMETER ResourceId
    X-Api-Resource-Id 资源标识；默认先试 seed-tts-2.0，若返回 45000030 未授权
    则自动回退为 volc.seedtts.default（部分新版控制台账号的授权挂在该资源下）。
    也可用环境变量 DOUBAO_TTS_RESOURCE_ID 固定指定。
.PARAMETER AppId
    覆盖环境变量 DOUBAO_APP_ID。
.PARAMETER ApiKey
    覆盖环境变量 DOUBAO_API_KEY（避免在命令行明文传 key 时慎用）。
.PARAMETER TimeoutSec
    单次请求超时秒数，默认 120。
.PARAMETER PricePer10kChars
    费用估算单价（元/万字符），仅用于日志估算，默认 5.0。
.PARAMETER LogFile
    用量日志 CSV 路径；默认 ~/.codex/logs/doubao-voice-usage.csv。
.PARAMETER NoLog
    不写用量日志。
.OUTPUTS
    生成的音频文件绝对路径（-ListSpeakers 时为音色列表）。
#>

[CmdletBinding()]
param(
    [string]$Text = '',
    [string]$TextFile = '',
    [string]$Speaker = 'zh_female_vv_uranus_bigtts',
    [ValidateSet('pcm', 'wav', 'mp3', 'ogg_opus', 'm4a', 'aac')]
    [string]$Format = 'pcm',
    [ValidateSet(8000, 16000, 22050, 24000, 32000, 44100, 48000)]
    [int]$SampleRate = 24000,
    [string]$OutFile = '',
    [switch]$Play,
    [switch]$NoSave,
    [int]$SpeechRate = 0,
    [string]$Emotion = '',
    [string]$Language = '',
    [switch]$CleanMarkdown,
    [switch]$ListSpeakers,
    [string]$BaseUrl = '',
    [string]$ResourceId = '',
    [string]$AppId = '',
    [string]$ApiKey = '',
    [int]$TimeoutSec = 120,
    [double]$PricePer10kChars = 5.0,
    [string]$LogFile = '',
    [switch]$NoLog
)

$ErrorActionPreference = 'Stop'

$script:DefaultBaseUrl = 'https://openspeech.bytedance.com'

function Write-Info {
    Write-Host $args -ForegroundColor DarkGray
}

function Get-BuiltinSpeakers {
    return @(
        [PSCustomObject]@{ Name = 'vivi 2.0（默认）';     Lang = 'cn'; Id = 'zh_female_vv_uranus_bigtts' }
        [PSCustomObject]@{ Name = '清晰小雪 2.0';          Lang = 'cn'; Id = 'zh_female_xiaoxue_uranus_bigtts' }
        [PSCustomObject]@{ Name = '小何';               Lang = 'cn'; Id = 'zh_female_xiaohe_uranus_bigtts' }
        [PSCustomObject]@{ Name = '云舟（男）';          Lang = 'cn'; Id = 'zh_male_m191_uranus_bigtts' }
        [PSCustomObject]@{ Name = '小天（男）';          Lang = 'cn'; Id = 'zh_male_taocheng_uranus_bigtts' }
        [PSCustomObject]@{ Name = 'Tim（男）';           Lang = 'en'; Id = 'en_male_tim_uranus_bigtts' }
        [PSCustomObject]@{ Name = 'Dacey（女）';         Lang = 'en'; Id = 'en_female_dacey_uranus_bigtts' }
        [PSCustomObject]@{ Name = 'Stokie（女）';        Lang = 'en'; Id = 'en_female_stokie_uranus_bigtts' }
    )
}

function New-PcmWavHeader {
    param([int]$Rate, [long]$DataLength)
    $bytes = New-Object 'System.Collections.Generic.List[byte]'
    $bytes.AddRange([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $bytes.AddRange([BitConverter]::GetBytes([uint32](36 + $DataLength)))
    $bytes.AddRange([Text.Encoding]::ASCII.GetBytes('WAVE'))
    $bytes.AddRange([Text.Encoding]::ASCII.GetBytes('fmt '))
    $bytes.AddRange([BitConverter]::GetBytes([uint32]16))
    $bytes.AddRange([BitConverter]::GetBytes([uint16]1))  # PCM
    $bytes.AddRange([BitConverter]::GetBytes([uint16]1))  # mono
    $bytes.AddRange([BitConverter]::GetBytes([uint32]$Rate))
    $bytes.AddRange([BitConverter]::GetBytes([uint32]($Rate * 2)))
    $bytes.AddRange([BitConverter]::GetBytes([uint16]2))  # block align
    $bytes.AddRange([BitConverter]::GetBytes([uint16]16)) # bits
    $bytes.AddRange([Text.Encoding]::ASCII.GetBytes('data'))
    $bytes.AddRange([BitConverter]::GetBytes([uint32]$DataLength))
    return $bytes.ToArray()
}

function Get-HttpErrorDetail {
    param($ErrorRecord)
    $status = $null
    try { $status = [int]$ErrorRecord.Exception.Response.StatusCode } catch { }
    $errMsg = ''
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $errMsg = $ErrorRecord.ErrorDetails.Message
    }
    if (-not $errMsg) { $errMsg = $ErrorRecord.Exception.Message }
    return @{ Status = $status; Message = $errMsg }
}

function Get-ApiCodeHint {
    param([int]$Code, [string]$Message)
    switch ($Code) {
        20000000 { return '' }
        45000001 { return "参数错误（$Message）" }
        45000030 { return "资源未授权（$Message）：若已开通语音合成2.0，脚本已自动尝试资源 volc.seedtts.default；仍失败请检查开通状态" }
        55000000 { return "资源与音色不匹配（$Message）：seed-tts-2.0 需要使用 *_uranus_bigtts 音色，或用 -ListSpeakers 查看内置音色" }
        55000001 { return "服务端会话错误（$Message），请重试" }
        default  { return "错误码 $Code（$Message）" }
    }
}

function Invoke-WavPlayback {
    param([string]$Path)
    # 优先 SoundPlayer（Windows PowerShell 5.1 可用），失败则退回 WinMM
    $soundPlayerType = $null
    foreach ($asm in @('System.Media', 'System.Windows.Extensions')) {
        try { Add-Type -AssemblyName $asm -ErrorAction Stop } catch { continue }
        $soundPlayerType = [type]::GetType('System.Media.SoundPlayer')
        if ($soundPlayerType) { break }
    }
    if ($soundPlayerType) {
        $player = New-Object $soundPlayerType($Path)
        try { $player.PlaySync() }
        finally { $player.Dispose() }
        return
    }

    # WinMM 兜底：mciSendString 播放 WAV（无窗口、无额外依赖）
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WinMM {
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern int mciSendString(string command, StringBuilder returnString, int returnLength, IntPtr hwndCallback);
}
'@ -ErrorAction Stop
    $null = [WinMM]::mciSendString('close codexvoice', $null, 0, [IntPtr]::Zero)
    $null = [WinMM]::mciSendString('open "' + $Path + '" type waveaudio alias codexvoice', $null, 0, [IntPtr]::Zero)
    $null = [WinMM]::mciSendString('play codexvoice wait', $null, 0, [IntPtr]::Zero)
    $null = [WinMM]::mciSendString('close codexvoice', $null, 0, [IntPtr]::Zero)
}

# ---------- 0. 音色列表 ----------
if ($ListSpeakers) {
    Get-BuiltinSpeakers | Format-Table Name, Lang, Id -AutoSize
    Write-Info '完整音色与 API 说明见 references/speakers.md'
    exit 0
}

# ---------- 1. 文本来源 ----------
if ($TextFile -and $Text) { throw '-Text 与 -TextFile 只能二选一' }
if ($TextFile) {
    if (-not (Test-Path -LiteralPath $TextFile)) { throw "文本文件不存在: $TextFile" }
    $Text = Get-Content -Raw -Encoding UTF8 -LiteralPath $TextFile
}
$Text = [string]$Text
if ([string]::IsNullOrWhiteSpace($Text)) { throw '必须提供 -Text 或 -TextFile' }
if ($NoSave -and -not $Play) { throw '-NoSave 需要与 -Play 一起使用（不保存时必须播放，否则合成结果会被丢弃）' }

# ---------- 2. 凭据 ----------
if (-not $AppId) { $AppId = $env:DOUBAO_APP_ID }
if (-not $ApiKey) { $ApiKey = $env:DOUBAO_API_KEY }
if (-not $ApiKey) {
    throw @'
缺少豆包语音 API Key：请设置环境变量 DOUBAO_API_KEY。
获取方式：火山引擎控制台 → 豆包语音 → 开通“语音合成大模型/TTS 2.0”→ APIKey 管理创建 API Key。
'@
}
if (-not $BaseUrl) { $BaseUrl = $script:DefaultBaseUrl }

# ---------- 3. 构建请求 ----------
$audioParams = @{ format = $Format; sample_rate = $SampleRate }
if ($SpeechRate -ne 0) { $audioParams.speech_rate = $SpeechRate }
if ($Emotion) { $audioParams.emotion = $Emotion }
if ($Language) { $audioParams.language = $Language }

$reqParams = @{
    text    = $Text
    speaker = $Speaker
    audio_params = $audioParams
}
if ($CleanMarkdown) {
    $reqParams.additions = '{"disable_markdown_filter":true}'
}

$body = @{
    user      = @{ uid = 'codex-desktop' }
    req_params = $reqParams
} | ConvertTo-Json -Depth 10

$headers = @{
    'X-Api-Key'        = $ApiKey
    'X-Api-Connect-Id' = [guid]::NewGuid().ToString('N')
}
if ($AppId) { $headers['X-Api-App-Id'] = $AppId }

$uri = $BaseUrl.TrimEnd('/') + '/api/v3/tts/unidirectional'
$resourceExplicit = [bool]($PSBoundParameters.ContainsKey('ResourceId') -and $ResourceId)
if (-not $ResourceId) {
    if ($env:DOUBAO_TTS_RESOURCE_ID) {
        $ResourceId = $env:DOUBAO_TTS_RESOURCE_ID
        $resourceExplicit = $true
    }
    else {
        $ResourceId = 'seed-tts-2.0'
    }
}

Write-Info "TTS 2.0 | 资源: $ResourceId | 音色: $Speaker | 格式: $Format | 采样率: $SampleRate | 字符数: $($Text.Length)"

# ---------- 4. 调用（自动重试 429/5xx；45000030 自动回退资源） ----------
$response = $null
$lastErr = $null
$fallbackTried = $false
for ($attempt = 0; $attempt -le 3; $attempt++) {
    $headers['X-Api-Resource-Id'] = $ResourceId
    try {
        $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec $TimeoutSec
        if ($response.Content -match '"code"\s*:\s*45000030') {
            $grantMsg = if ($response.Content -match '"message"\s*:\s*"([^"]*not granted[^"]*)"') { $Matches[1] } else { 'requested resource not granted' }
            if (-not $resourceExplicit -and -not $fallbackTried -and $ResourceId -ne 'volc.seedtts.default') {
                $fallbackTried = $true
                $ResourceId = 'volc.seedtts.default'
                Write-Info "资源未授权（45000030：$grantMsg），自动改用 volc.seedtts.default 重试"
                $response = $null
                continue
            }
            $lastErr = @{ Status = 403; Message = "资源未授权（45000030）：$grantMsg（当前资源 $ResourceId）" }
            $response = $null
            break
        }
        $lastErr = $null
        break
    }
    catch {
        $lastErr = Get-HttpErrorDetail -ErrorRecord $_
        $retryable = ($null -eq $lastErr.Status) -or ($lastErr.Status -eq 429) -or ($lastErr.Status -ge 500 -and $lastErr.Status -le 599)
        if ($retryable -and $attempt -lt 2) {
            Write-Info ("请求失败（{0}），{1} 秒后重试..." -f $lastErr.Status, (2 * ($attempt + 1)))
            Start-Sleep -Seconds (2 * ($attempt + 1))
            continue
        }
        break
    }
}

if (-not $response) {
    $hint = switch ($lastErr.Status) {
        401 { 'API Key 无效或未授权，请检查 DOUBAO_API_KEY' }
        403 { '无权限：确认已开通“语音合成大模型/TTS 2.0”，且账户已完成实名认证、余额正常' }
        404 { "接口不存在：确认 BaseUrl 正确（国内默认 openspeech.bytedance.com）" }
        429 { '请求过于频繁（限流），请稍后再试' }
        default { '豆包语音 TTS 调用失败' }
    }
    throw "$hint：$($lastErr.Message)"
}

# ---------- 5. 解析 NDJSON 流并拼装音频 ----------
$audioStream = New-Object System.IO.MemoryStream
$done = $false
$errorDetail = ''
$lines = [regex]::Split([string]$response.Content, "\r?\n")
foreach ($line in $lines) {
    $t = $line.Trim()
    if (-not $t) { continue }
    $obj = $null
    try { $obj = $t | ConvertFrom-Json } catch { continue }
    if ($null -eq $obj) { continue }

    $code = 0
    try { $code = [int]$obj.code } catch { }
    if ($code -ne 0 -and $code -ne 20000000) {
        $errorDetail = Get-ApiCodeHint -Code $code -Message ([string]$obj.message)
        break
    }
    if ($obj.data) {
        $chunk = [Convert]::FromBase64String([string]$obj.data)
        if ($chunk.Length -gt 0) { $audioStream.Write($chunk, 0, $chunk.Length) }
    }
    if ($obj.done -or $code -eq 20000000) { $done = $true; break }
}
$audioBytes = $audioStream.ToArray()
$audioStream.Dispose()

if ($errorDetail) { throw "豆包语音返回错误：$errorDetail" }
if ($audioBytes.Length -eq 0) { throw '未收到音频数据（可能文本为空或音色不支持当前语言）' }
if (-not $done) { Write-Info '警告：响应流未收到结束标记，但已按收到内容保存' }

# ---------- 6. 写出文件 ----------
if (-not $OutFile) {
    $ext = if ($Format -eq 'pcm') { 'wav' } else { $Format }
    if ($NoSave) {
        $OutFile = Join-Path $env:TEMP ('doubao-voice-' + [guid]::NewGuid().ToString('N') + '.' + $ext)
    }
    else {
        $outDir = Join-Path $HOME '.codex\logs\doubao-voice'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $OutFile = Join-Path $outDir ('tts-' + (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '.' + $ext)
    }
}
$outDir2 = Split-Path $OutFile -Parent
if ($outDir2 -and -not (Test-Path $outDir2)) { New-Item -ItemType Directory -Path $outDir2 -Force | Out-Null }

if ($Format -eq 'pcm') {
    $header = New-PcmWavHeader -Rate $SampleRate -DataLength $audioBytes.Length
    $fs = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create)
    try {
        $fs.Write($header, 0, $header.Length)
        $fs.Write($audioBytes, 0, $audioBytes.Length)
    }
    finally { $fs.Dispose() }
}
else {
    [System.IO.File]::WriteAllBytes($OutFile, $audioBytes)
}

# ---------- 7. 播放 ----------
if ($Play) {
    if ($Format -ne 'pcm' -and $Format -ne 'wav') {
        if ($NoSave) { [System.IO.File]::Delete($OutFile) }
        throw '当前仅 pcm/wav 支持直接播放；请用 -Format pcm（默认）或 wav，或手动打开生成的音频文件'
    }
    Invoke-WavPlayback -Path $OutFile
    Write-Info "已播放: $OutFile"
    if ($NoSave) {
        [System.IO.File]::Delete($OutFile)
        Write-Info '临时音频已删除（-NoSave 不保留文件）'
    }
}

# ---------- 8. 用量估算与日志 ----------
try {
    $cost = [math]::Round($Text.Length / 10000.0 * $PricePer10kChars, 6)
    Write-Info ("估算用量: {0} 字符 | 费用 ≈ ¥{1:N4}（单价 {2} 元/万字符，以控制台账单为准）" -f $Text.Length, $cost, $PricePer10kChars)
    if (-not $NoLog) {
        $logPath = if ($LogFile) { $LogFile } else { Join-Path $HOME '.codex\logs\doubao-voice-usage.csv' }
        $logDir = Split-Path $logPath -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $q = if ($Text.Length -gt 80) { $Text.Substring(0, 80) } else { $Text }
        [PSCustomObject]@{
            Timestamp   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Speaker     = $Speaker
            Format      = $Format
            SampleRate  = $SampleRate
            Chars       = $Text.Length
            CostYuan    = $cost
            OutFile     = if ($NoSave) { '(未保存)' } else { $OutFile }
            TextPreview = $q
        } | Export-Csv -Path $logPath -Append -NoTypeInformation -Encoding UTF8
        Write-Info "用量日志: $logPath"
    }
}
catch { Write-Info ("用量日志写入失败: " + $_.Exception.Message) }

if ($NoSave) { Write-Output '(未保存，仅播放)' } else { Write-Output $OutFile }
