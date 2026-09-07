# Doubao Vision — 给 Codex 装上豆包的眼睛

一个开箱即用的 Codex 视觉技能（Skill）：由火山方舟的 **Doubao-Seed-2.0-mini** 完成图片识别，并把文字/JSON 结果返回给主模型。支持用户上传图片、本地图片、网络图片 URL 与屏幕截图。

> **项目背景**：创建时 DeepSeek 尚不支持识图，本仓库最初用于给纯文本模型“补眼睛”。如今 DeepSeek 已具备图片理解能力，本技能定位调整为**补充 / 备用视觉通道**，在以下场景仍然有用：
>
> - 需要专门视觉能力时：屏幕截图分析、多图对比、OCR 与局部放大、GUI 元素定位、直方图等；
> - 运行在仍不支持图片输入的其他文本模型 / Codex 会话上；
> - 希望把“看图”职责与主模型解耦，走独立、可计量的视觉 API。

无需本地显卡推理，**按量付费、成本极低**（每百万 token 输入 0.2 元 / 输出 2 元）。

## 功能特性

- 用户上传图片自动识图（中文触发词：上传图片 / 看图 / 识图 / 分析照片 / 描述截图）
- 本地图片、网络图片 URL、屏幕截图（`-Screenshot`）三种输入
- 多图对比（`-Images`，例如修图前后）
- 视觉质量三档：`low / high / xhigh`（细节密集用 xhigh）
- 裁剪放大：原图坐标 `-Crop` / 模型视图坐标 `-CropView`（自动换算）
- JSON 结构化输出（自动剥离 ```` ```json ```` 围栏）
- EXIF 方向自动转正（手机竖拍图不乱）
- 429/5xx 自动重试，401/403/404 给出具体修复提示
- 每次调用输出 token 用量与估算费用，可写 CSV 日志

## 目录结构

```text
doubao-vision/
├── SKILL.md                  # 技能说明（Codex 读取）
├── agents/openai.yaml        # 技能界面元数据
├── scripts/
│   └── doubao-vision.ps1     # 核心脚本（唯一需要运行的文件）
├── references/
│   └── prompts.md            # 提示词模板
├── README.md
├── LICENSE
└── .gitignore
```

## 快速开始

### 1. 前提条件

- Windows + PowerShell 7（`pwsh`）；macOS/Linux 可用 `pwsh` 运行，命令相同
- 一个火山方舟账号（[volcengine.com](https://www.volcengine.com)）

### 2. 开通模型并获取 API Key

1. 登录火山引擎控制台，进入**火山方舟**；
2. 在「开通管理」中开通模型 **Doubao-Seed-2.0-mini**（模型 ID：`doubao-seed-2-0-mini-260215`）；
3. 在「API Key 管理」中创建一个 API Key。

### 3. 安装技能

```powershell
# 克隆或下载本项目后，把内容复制到 Codex 技能目录
git clone https://github.com/<你的用户名>/doubao-vision.git
Copy-Item doubao-vision\* "$env:USERPROFILE\.codex\skills\doubao-vision\" -Recurse
```

然后**完全退出并重启 Codex**（让新会话加载技能）。

### 4. 配置 API Key（只走环境变量，绝不写入代码）

Windows：

```powershell
setx ARK_API_KEY "你的_API_Key"
```

macOS / Linux：

```bash
echo 'export ARK_API_KEY="你的_API_Key"' >> ~/.zshrc
source ~/.zshrc
```

> 设置后需要**重启终端 / Codex** 才生效（已运行的进程不会自动继承）。

### 5. 验证

新开一个 Codex 聊天窗口，直接上传一张图片，或手动运行：

```powershell
pwsh -File scripts/doubao-vision.ps1 -Image C:\path\photo.jpg -Question "这张图里有什么？"
```

看到类似输出即成功：

```text
用量: 输入 1333 tokens（缓存 0）| 输出 142 tokens | 估算费用 ¥0.00055
这张图里有一个红色实心圆和文字 "SIGHT-TEST-7731"。
```

## 常用命令

```powershell
# 查找用户最近上传的图片（30 分钟内）
pwsh -File scripts/doubao-vision.ps1 -FindRecent -RecentMinutes 30

# 分析本地图片
pwsh -File scripts/doubao-vision.ps1 -Image C:\path\photo.jpg -Question "识别这张图并描述内容"

# 截取当前屏幕
pwsh -File scripts/doubao-vision.ps1 -Screenshot -Question "当前界面显示什么？"

# JSON 结构化输出（建议在问题中明确要求返回 JSON）
pwsh -File scripts/doubao-vision.ps1 -Image C:\path\photo.jpg -Question "用 JSON 描述这张图" -Json

# 多图对比
pwsh -File scripts/doubao-vision.ps1 -Images C:\path\before.jpg,C:\path\after.jpg -Question "对比这两张图"

# 裁剪放大局部（模型视图坐标，自动换算回原图）
pwsh -File scripts/doubao-vision.ps1 -Image C:\path\photo.jpg -CropView 600,300,1200,1200 -Detail xhigh -Question "检查星点锐度"
```

## 参数说明

| 参数 | 说明 |
|---|---|
| `-Image` | 本地图片路径 |
| `-Images` | 多张图片（逗号分隔），用于对比 |
| `-Screenshot` | 截取当前虚拟屏幕 |
| `-FindRecent` / `-RecentMinutes N` | 查找最近 N 分钟内常见目录里的图片 |
| `-Question` | 识别/分析要求 |
| `-Detail` | 视觉质量 `low / high / xhigh`，默认 `high` |
| `-MaxSize` | 最长边缩放上限（默认 1280） |
| `-Crop` | 原图坐标裁剪 `x,y,w,h` |
| `-CropView` | 视图坐标裁剪（自动换算回原图） |
| `-Json` | 要求并校验 JSON 输出 |
| `-LogFile` / `-NoLog` | 用量日志 CSV 路径 / 关闭日志 |
| `-Model` | 覆盖默认模型 `doubao-seed-2-0-mini-260215` |
| `-TimeoutSec` | 请求超时（默认 600） |

## 费用参考

Doubao-Seed-2.0-mini 按量计费（≤32K 输入区间）：

- 输入：0.2 元 / 百万 tokens
- 输出：2 元 / 百万 tokens
- 缓存命中：0.04 元 / 百万 tokens

一次普通识图约 0.0005～0.005 元；每次调用脚本都会打印实际用量和估算费用。

## 故障排查

| 现象 | 原因 | 解决 |
|---|---|---|
| 401 Unauthorized | API Key 无效 | 检查 `ARK_API_KEY` 环境变量 |
| 403 | 无权限或余额不足 | 检查方舟控制台账户状态 |
| 404 模型不存在 | 模型未开通或 ID 错误 | 在「开通管理」开通 `doubao-seed-2-0-mini-260215` |
| 429 限流 | 请求过于频繁 | 稍等后重试（脚本已自动重试 2 次） |
| 报“缺少 API 密钥” | 环境变量未继承 | 重启终端 / Codex |

## 安全说明

- **本项目不包含任何 API Key**，密钥只通过环境变量 `ARK_API_KEY` 提供；
- 请勿把 Key 写入任何配置文件并提交到 GitHub；
- `.gitignore` 已排除 `.env`、日志、临时文件；
- 用量日志默认写在 `~/.codex/logs/`，不会进入仓库。

## 更新记录

- 2026-09-07：README 更新——DeepSeek 现已支持识图，不再将其描述为“纯文本模型”；项目定位调整为 Codex 的补充 / 备用视觉通道，用于截图、多图对比、OCR、局部放大等专门场景。
- 2026-08-02：修复 Windows PowerShell 5.1 下中文请求体乱码（请求体改为 UTF-8 字节发送，中文提示词不再被误判为“乱码”）；脚本保存为带 BOM 的 UTF-8，PowerShell 5.1 与 7 均可直接运行；调用方式建议优先 `pwsh -File`；移除仓库内的声音技能（已迁移至独立仓库 [doubao-voice-for-Codex](https://github.com/EonGreen0/doubao-voice-for-Codex)），本仓库恢复为单一视觉技能结构。

## 许可证

[Unlicense](LICENSE)（公有领域授权，沿用仓库创建时的选择）
