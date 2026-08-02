---
name: doubao-voice
description: >-
  Codex 的声音：用豆包语音合成 2.0（seed-tts-2.0）把文字合成语音并朗读/播放。
  当用户要求朗读、语音播报、把回复/文本变成声音、TTS、播放音频、有声书式朗读，
  或需要把 Codex 的文字回复念出来时使用。需要 DOUBAO_APP_ID 与 DOUBAO_API_KEY 环境变量。
---

# Doubao Voice（Codex 的声音）

这是 Codex 在纯文本模型下的“嘴”：`scripts/doubao-tts.ps1` 把文本发给豆包语音合成 2.0，
合成音频（默认 pcm 自动包装成 wav），输出文件路径并可选直接播放，无需 ffmpeg。

## 前置条件

- 火山引擎控制台已开通豆包语音“语音合成大模型/TTS 2.0”，并设置环境变量：
  - `DOUBAO_API_KEY`：豆包语音控制台 → APIKey 管理创建的 API Key。
    **注意：必须是豆包语音（语音技术）控制台的 key，火山方舟 `ark-` 开头的 key 不适用于本接口。**
  - `DOUBAO_APP_ID`（可选）：旧版鉴权或个别账号需要时才设置，新版控制台鉴权仅用 X-Api-Key。
  - `DOUBAO_TTS_RESOURCE_ID`（可选）：固定 X-Api-Resource-Id；默认自动处理，无需设置。
- 未配置时脚本会报错，Codex 应提示用户配置环境变量后重试。
- 调用统一使用 `pwsh -File` 或 `powershell -ExecutionPolicy Bypass -File`（脚本已保存为带 BOM 的 UTF-8，Windows PowerShell 5.1 与 PowerShell 7 均可直接解析）。

## 快速开始（Codex 朗读工作流）

用户要求朗读时，先生成回复文本，再调用脚本：

```powershell
# 朗读一段文本
pwsh -File C:\Users\SANWU\.codex\skills\doubao-voice\scripts\doubao-tts.ps1 -Text "您好，这是豆包语音合成的朗读效果。" -Play

# 朗读文件内容（长文本建议先写入 UTF-8 文件）
pwsh -File ...\doubao-tts.ps1 -TextFile C:\path\reply.txt -Play

# 只生成音频不播放
pwsh -File ...\doubao-tts.ps1 -Text "..." -OutFile C:\path\out.wav

# 只朗读不留文件（播放后自动清理）
pwsh -File ...\doubao-tts.ps1 -Text "..." -Play -NoSave

# 查看内置音色
pwsh -File ...\doubao-tts.ps1 -ListSpeakers
```

注意：
- 默认保存音频到 `~/.codex/logs/doubao-voice/`；不需要留文件时加 `-NoSave`（需配合 `-Play`）。
- `-Play` 会同步阻塞直到朗读结束，结束后再向用户确认。
- 朗读 Codex 回复时建议加 `-CleanMarkdown`，`**加粗**`、列表符号等会被按正常语义朗读。
- 长文本先精简或分段（每段建议不超过 2000 字），逐段调用并拼接。
- 播放仅支持 `pcm`（默认）与 `wav`；`mp3` 等格式只保存文件。

## 核心参数

- `-Text` / `-TextFile`：朗读文本（二选一）。
- `-Speaker`：音色 ID，默认 `zh_female_vv_uranus_bigtts`（vivi 2.0）；`-ListSpeakers` 查看内置列表。
- `-Format`：pcm（默认）/ wav / mp3 / ogg_opus / m4a / aac。
- `-SampleRate`：24000 默认，可选 8000~48000。
- `-Play`：合成后播放；`-NoSave`：不保存音频文件（播放后自动清理）；`-OutFile`：指定输出路径。
- `-SpeechRate`（-50~100）、`-Emotion`、`-Language`（如 zh-cn）、`-CleanMarkdown`。
- `-BaseUrl`：默认国内 `https://openspeech.bytedance.com`；BytePlus 国际站可覆盖。

## 排错要点

- `55000000 resource ID is mismatched`：音色与资源不匹配，seed-tts-2.0 必须用 `*_uranus_bigtts` 音色。
- 401/403：检查 API Key、服务开通状态、账户实名认证与余额。
- `45000010 Invalid X-Api-Key`：`DOUBAO_API_KEY` 类型不对，请到豆包语音控制台 APIKey 管理重新创建（不要用火山方舟的 ark- key）。
- `45000030 requested resource not granted`：账号授权挂在 `volc.seedtts.default` 等资源名下时，脚本会自动从 `seed-tts-2.0` 回退重试；仍失败则检查“语音合成大模型”开通状态，或用 `-ResourceId` / `DOUBAO_TTS_RESOURCE_ID` 指定。
- `未收到音频数据`：文本可能为空、全为不支持字符，或音色不支持所选语言，改用 `zh-cn` 或换音色。
- 用量与费用：脚本按字符估算并写 CSV 日志（默认 `~/.codex/logs/doubao-voice-usage.csv`，单价 5 元/万字符可调），实际以控制台账单为准。

## 参考

- 音色列表与 API 字段说明：[references/speakers.md](references/speakers.md)
