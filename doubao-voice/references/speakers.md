# 豆包语音合成 2.0：音色与接入参考

## 常用音色（seed-tts-2.0 资源）

| 名称 | 场景 | 语言 | Voice ID |
|---|---|---|---|
| vivi 2.0（默认） | 通用 | cn | `zh_female_vv_uranus_bigtts` |
| 清晰小雪 2.0 | 通用 | cn | `zh_female_xiaoxue_uranus_bigtts` |
| 小何 | 通用 | cn | `zh_female_xiaohe_uranus_bigtts` |
| 云舟 | 通用 | cn | `zh_male_m191_uranus_bigtts` |
| 小天 | 通用 | cn | `zh_male_taocheng_uranus_bigtts` |
| Tim | 通用 | en | `en_male_tim_uranus_bigtts` |
| Dacey | 通用 | en | `en_female_dacey_uranus_bigtts` |
| Stokie | 通用 | en | `en_female_stokie_uranus_bigtts` |

规则：`seed-tts-2.0` 资源优先使用 `*_uranus_bigtts` 音色；`seed-tts-1.0` 使用 `*_moon_bigtts`。
控制台音色库中 `*_saturn_bigtts`、`saturn_*_tob` 等音色需账户级开通且与资源匹配，否则报
`55000000 resource ID is mismatched with speaker related resource`。

方言：`zh_female_vv_uranus_bigtts` 支持 `dongbei`、`shaanxi`、`sichuan`
（通过 `additions` 的 `explicit_dialect` 传入）。

## 接入协议（脚本已实现）

- 端点：`POST https://openspeech.bytedance.com/api/v3/tts/unidirectional`
  （BytePlus 国际站：`https://voice.ap-southeast-1.bytepluses.com`）。
- 鉴权头：`X-Api-Key`（必须，豆包语音控制台 APIKey 管理创建；火山方舟 ark- key 无效）、
  `X-Api-Resource-Id: seed-tts-2.0`（必须）、`X-Api-Connect-Id`（连接追踪，建议每次唯一）。
- 新版控制台鉴权仅使用 `X-Api-Key`，不要混用 `X-Api-App-Id` / `X-Api-Access-Key`；
  脚本在设置 `DOUBAO_APP_ID` 时才会附带 `X-Api-App-Id`。
- 请求体：
  ```json
  {
    "user": { "uid": "codex-desktop" },
    "req_params": {
      "text": "要朗读的文字",
      "speaker": "zh_female_vv_uranus_bigtts",
      "audio_params": { "format": "pcm", "sample_rate": 24000 }
    }
  }
  ```
- 响应：HTTP 200，body 为换行分隔 JSON（NDJSON），每行
  `{"code":0,"message":"","done":false,"data":"<base64 音频分片>"}`，
  最后一行 `done:true`（或 code=20000000）。
- `audio_params.format`：`mp3` / `pcm` / `wav` / `ogg_opus` / `aac` / `m4a`；
  `pcm` 为 16bit 小端单声道裸流，脚本本地补 WAV 头。
- `audio_params.sample_rate`：8000 / 16000 / 22050 / 24000 / 32000 / 44100 / 48000。

## 常用可选字段

| 字段 | 说明 |
|---|---|
| `audio_params.speech_rate` | 语速 -50~100，100 为 2 倍速 |
| `audio_params.loudness_rate` | 音量 -50~100（WebSocket 文档名） |
| `audio_params.emotion` | 情感参数，视音色支持 |
| `audio_params.language` | 显式语言：zh-cn / en / ja / es-mx / id / pt-br / ko |
| `req_params.additions` | JSON 字符串扩展参数，如 `{"disable_markdown_filter":true}` 让 Markdown 按语义朗读 |

## 错误码速查

| 错误码 | 含义 |
|---:|---|
| `20000000` | 成功 |
| `45000001` | 请求参数错误 |
| `45000030` | 资源未授权：授权可能挂在 `volc.seedtts.default` 而非 `seed-tts-2.0`，脚本会自动回退重试 |
| `55000000` | 服务端错误（常见：资源与音色不匹配） |
| `55000001` | 服务端会话错误 |

资源 ID 说明：标准写法为 `seed-tts-2.0`；部分新版控制台账号的授权实际挂在
`volc.seedtts.default`（脚本遇到 45000030 会自动回退）。也可用
`DOUBAO_TTS_RESOURCE_ID` 环境变量或 `-ResourceId` 参数固定指定。

## 计费口径

按合成文本字符数计费（含标点）。个人低频朗读可先用控制台免费额度；
脚本日志默认按 5 元/万字符估算，实际以控制台开通页价格为准。
