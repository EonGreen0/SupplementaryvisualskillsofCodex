---
name: doubao-vision
description: >-
  Default vision backend for text-only Codex models: recognize and analyze any
  image with Doubao-Seed-2.0-mini (Volcano Ark) and return text/JSON. Use
  whenever the main model needs to see an image but cannot accept image inputs:
  user-uploaded images (上传图片/看图/识图/分析照片/描述截图), local photos,
  screenshots, UI captures, reading text or OCR, describing scenes, answering
  questions about visual content, or any task that needs visual judgment.
  Requires the ARK_API_KEY environment variable.
---

# Doubao Vision（Codex 的视觉）

这是 Codex 在纯文本模型下的“眼睛”：`scripts/doubao-vision.ps1` 把图片发给火山方舟 Doubao-Seed-2.0-mini，把识别结果（文字/JSON）打印到 stdout，主模型读取后继续判断和回复。

## 前置条件

- 火山方舟已开通模型 `doubao-seed-2-0-mini-260215`，并设置环境变量 `ARK_API_KEY`。
- 未配置时脚本会报错，遇到 `ARK_API_KEY missing` 错误时，Codex 应直接提示用户配置环境变量并重试。
- 跨平台与执行策略：为了保证多平台兼容与绕过 Windows 默认限制，建议 Codex 调用时统一使用 `pwsh -File` 或 `powershell -ExecutionPolicy Bypass -File`。
- 示例中的 `scripts/doubao-vision.ps1` 是技能目录相对路径；调用时建议使用技能目录的绝对路径，或先切换到技能目录再执行。

## 使用场景（Codex 视觉）

只要主模型需要“看”图，就走这个流程：

1. 定位图片：
   - **用户上传文件**：先用 `scripts/doubao-vision.ps1 -FindRecent -RecentMinutes 30` 查找。若找到多张，默认取时间最新的一张并明确告知用户（例如“我找到了您刚才上传的 image.png”）；若无法确定，列出候选图片列表让用户确认。
   - **本地文件**：直接传入 `-Image <路径>`。
   - **网络图片 (URL)**：Codex 需先使用命令行工具（如 `curl` 或 `Invoke-RestMethod`）将图片下载至临时目录，再调用脚本处理。
   - **屏幕截图**：使用 `-Screenshot` 截取当前屏幕。
2. 调用 `scripts/doubao-vision.ps1 -Image <路径> -Question "<识别/分析要求>"`。
   - **注意**：若使用了 `-Json` 参数，建议在 `-Question` 中明确要求返回 JSON（例如写“用 JSON 返回…”）；否则模型可能返回普通文本，`-Json` 校验会失败并输出原文，这不是 API 报错。
3. 把脚本返回的文字/JSON 整理后回复用户，或依据结果继续后续操作。如果遇到 API 限流 (429) 或网络超时，应提示用户稍作等待、检查网络或尝试缩减图片大小。

## 快速开始

```powershell
# 查找用户最近上传的图片
pwsh -File scripts/doubao-vision.ps1 -FindRecent -RecentMinutes 30

# 分析图片（用户上传 / 本地文件）
pwsh -File scripts/doubao-vision.ps1 -Image C:\path\photo.jpg -Question "识别这张图并描述内容"

# 截取当前屏幕分析
pwsh -File scripts/doubao-vision.ps1 -Screenshot -Question "当前界面显示什么？"

# 要求 JSON 结构化输出（建议在问题中明确要求返回 JSON）
pwsh -File scripts/doubao-vision.ps1 -Image C:\path\photo.jpg -Question "用 JSON 描述这张图的场景和文字" -Json

# 多图对比（如修图前后）
pwsh -File scripts/doubao-vision.ps1 -Images C:\path\before.jpg,C:\path\after.jpg -Question "对比这两张图的区别"
```

## 参数

- `-Image`：本地图片路径；`-Images a.jpg,b.jpg`：多图对比；`-Screenshot`：截取当前屏幕。
- `-FindRecent [-RecentMinutes N]`：列出最近 N 分钟内常见目录里的图片后退出（定位上传文件用）。
- `-Question`：识别/分析要求，默认整体描述。配合 `-Json` 使用时建议在问题中明确要求返回 JSON。
- `-Detail`：视觉质量档位 low/high/xhigh，默认 high；细节密集用 xhigh（更慢更耗 token）。
- `-MaxSize`：最长边缩放上限（默认 1280）。
- `-Crop x,y,w,h`：按**原图坐标**裁剪放大；`-CropView x,y,w,h`：按**模型看到的视图坐标**裁剪（脚本自动换算回原图）。
- `-Json`：要求并校验 JSON 输出（自动剥离 ```json 围栏）。
- `-LogFile`：用量日志 CSV（默认 `~/.codex/logs/doubao-vision-usage.csv`）；`-NoLog` 关闭。
- `-Model`：默认 `doubao-seed-2-0-mini-260215`，可覆盖；`-TimeoutSec` 默认 600。

## 坐标约定（重要）

- 让模型返回坐标时，把脚本输出的“视图尺寸”（例如 1920 x 1280）写进问题里，要求按视图尺寸返回。
- 拿到视图坐标后用 `-CropView` 传入，脚本自动换算成原图坐标；不要直接把视图坐标当原图坐标用。
- 参考模板见 references/prompts.md。

## 要点

- 脚本自动处理：EXIF 方向转正、429/5xx 重试、401/403/404 等错误原因提示、token 用量与费用统计。
- 图片越大越慢越贵；精细问题先裁剪放大，再配合 `-Detail xhigh`。
- 要求结构化输出时，在问题里给出明确 JSON schema，**并建议在提问中明确要求返回 JSON**（模板见 references/prompts.md）。
- 模型回答不稳定时，收紧问题范围（脚本默认 temperature 0.2）。

## 参考

- 提示词模板（通用识图、照片 QA、GUI 定位、直方图、多图对比）：[prompts.md](references/prompts.md)
