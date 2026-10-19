Current selection (2026-10-16): the user superseded Lite with **Seedream 5.0 Flash**. Default official service profile and direct adapter selection now use `doubao-seedream-5-0-flash-260915`, public price 12 fen/image. Pro is an explicit optional profile (60 fen for configured standard 2K). Network remains disabled by default; no real Flash request was sent. Restart the user-managed service with the unchanged `start_official.ps1` entry to load Flash after confirming its account activation. Do not silently reuse an old Pro process. See [current service configuration and recovery](../local_image_service/README.md). The fourth authorized Pro request already returned a verified 2368x1776 PNG in 39.876 seconds; older attempt/preparation notes below are historical. The third lost response's cause remains unproven.

# 独立图像生成服务包（Godot 4.7.2）

当前真实服务约束为**国内厂商官方 API，禁止国外服务与第三方中转**。用户已选择 Seedream 5.0 Pro：standard、2K、单张绘画参考图、单图输出，不做图层拆分或组图。本轮 10 元预算、该 0.60 元档最多 16 次。已执行一次授权真实联调，返回 502/未知结果，未取得图片；保留 60 分，实际计费未知。[安全诊断与下一步](../local_image_service/DIAGNOSTICS.md)。模型须由 provider 显式注入，通用业务没有默认或自动升级。下文 OpenAI/Gemini/代理为历史实现与研究，不作为当前真实路由。

输入一张 `Image` 和提示词，异步返回一张 `Image` 或结构化错误。没有桥、船、绘画、关卡、autoload 或插件依赖；不修改主场景。当前可验收的是 **离线 MOCK**，着色结果不是 AI 生成图片。

新增真实本机 HTTP 联通入口：`res://image_generation/loopback_demo.tscn`，默认 **STUB 原图回传，非 AI**。独立服务、用户交互式密钥配置和给关卡的接口见 [local_image_service/README.md](../local_image_service/README.md)。Godot 不接收厂商密钥；本轮诊断修复仅用模拟/本机 stub，没有再次发送真实请求或重启用户服务。

## 立即运行离线演示

Godot 打开现有工程，打开 `res://image_generation/demo.tscn`，按 F6。演示使用代码合成的蓝色方块图片；输入提示词，点击“运行离线模拟”，可切换成功、限流、超时、无效响应和网络错误；生成中可取消。提示词哈希决定模拟着色，不解释提示词语义。

也可以从项目根目录运行（替换本机 Godot 控制台路径）：

```powershell
& 'Godot_v4.7.2-stable_win64_console.exe' --path . res://image_generation/demo.tscn
& 'Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/image_generation/verify_image_generation.gd
```

演示不读文件或环境变量，不建 HTTPRequest，不上传图片，不请求凭证，不产生 API 费用。成功结果只在内存中显示，不自动落盘。

## 复用接口

```gdscript
const Service = preload("res://image_generation/service.gd")
const Request = preload("res://image_generation/request.gd")
const Proxy = preload("res://image_generation/proxy_provider.gd")
const Mock = preload("res://image_generation/mock_transport.gd")

var service = Service.new()
var provider = Proxy.new()
provider.endpoint = "https://offline.invalid/image-generation"
service.provider = provider
service.transport_factory = func(): return Mock.new()
add_child(service)

var job = service.generate(Request.new(my_image, "转换为水彩画"))
var result = await job.finished
if result.ok:
    var texture = ImageTexture.create_from_image(result.image)
else:
    show_error(result.error.code, result.error.message)
# 生成完成前可以 job.cancel()；已完成后取消无效。
```

`generate()` 同步复制输入像素与提示词，下一次 deferred 调度才开始，因此调用后可直接连接 `finished` 或 await。`job.done`、`job.result` 可供晚订阅者检查。每个 job 完成一次；同一 service 可同时运行多个独立 job。移除 service 会取消未完成任务。只在主线程调用这些对象。调用方负责在切换页面时取消任务，并决定如何显示/保存返回图片。

| 类型 | 约定 |
| --- | --- |
| Request | `image: Image`、`prompt: String`、`timeout_seconds: float`（默认 60，允许 0.01–600） |
| Result | `ok: bool`、成功时 `image: Image`；失败时 `error: Dictionary` |
| error | `code`、可显示的固定 `message`、`http_status`、`outcome_unknown`、`automatic_retry=false` |
| provider | `encode(snapshot) -> {wire}` 或 `{failure}`；`decode(status, body) -> Result` |
| snapshot | 内部 `png: PackedByteArray` 和 `prompt: String`，不含凭证 |
| wire | `url: String`、`headers: PackedStringArray`、`body: PackedByteArray`，内部数据禁止记录 |
| transport | 每 job 一个未挂树 Node；`start(wire, callback) -> Error`；`cancel()` |
| callback | `{status: int, body: PackedByteArray}` 或 `{transport_error: true}`；允许同步回调；完成后迟到回调被忽略 |

传输层 `start` 非 OK 表示没有发出请求；自定义传输层如果无法保证这一点，应返回 OK，再通过 `transport_error` 回调报告不确定状态。工厂和 provider 是受信任代码注入点；不接受终端用户自定义脚本。

工厂返回一个未挂树 Node 即向服务移交所有权；即使它缺少 `start` / `cancel`，服务也会拒绝请求并将其 `queue_free()`。已挂树 Node 仍属于外部所有者，服务拒绝但不调用它的钩子、不释放它。清理开始后忽略同步回调和再次取消；先停止计时器、取消并安排释放传输节点、移除活动任务，再发出一次 `finished`。节点实际释放遵循 Godot 帧末的 `queue_free()` 时序。

输入限制为一张非空图片，宽高各不超过 4096，编码后 PNG 不超过 8 MiB；提示词去空白后非空，原文不超过 32000 字符。原协议只接收 PNG；Seedream 4.5 适配器另接收 JPEG，均为 8 MiB/4096 边长限制，解码前检查尺寸。HTTP 响应上限 24 MiB。不自动缩放、丢图、下载返回 URL、批量输出或降级模型。

错误码包括 `invalid_input`、`configuration`、`transport_start`、`cancelled`、`timeout`、`network`、`unauthorized`、`rate_limited`、`rejected`、`provider_error`、`response_too_large`、`invalid_response`、`invalid_image`。不转发上游错误原文，不记录提示词、图片/base64、HTTP headers 或凭证。

取消和超时只停止本地等待/连接，**不保证服务商停止生成或免收费**。发出后取消、超时、网络失败、5xx 或损坏成功响应会标注 `outcome_unknown=true`。所有路径均不自动重试，包括 429；再次生成必须由上层明确发起，可能重复收费。当前接口没有端到端幂等承诺。

## 安全接通边界

默认没有网络开关、模型默认值或认证读取。`http_transport.gd` 必须显式设置 `enabled=true`、完整 HTTPS `allowed_urls` 才允许发送；禁止重定向、URL 凭证及查询串，使用引擎默认 TLS 验证。认证可通过运行时 `transient_headers: Callable -> PackedStringArray` 注入。该回调不序列化、不读环境变量、不提供凭证持久化功能；它也不意味着公共客户端能安全保管密钥。

**公开展厅机器不能包含服务商长期密钥**，包括 Godot 脚本、资源、项目配置、导出程序、打包环境文件和日志。推荐由另行部署的受控后端持有服务商密钥，后端执行身份/设备授权、额度、限流、输入上限、审计脱敏及费用控制。终端仅获得受限短期会话授权。这个后端本轮没有创建；是否采用、谁部署、认证与网络策略，仍需明确决策。单纯将长期密钥藏在客户端回调里不解决泄露风险。

`proxy_provider.gd` 提供 **项目自有、尚未部署的 v1 协议**：

```json
// 请求（POST 到受控 HTTPS endpoint）
{"schema_version":1,"prompt":"...","image":{"mime_type":"image/png","base64":"..."}}
// 200 响应
{"schema_version":1,"image":{"mime_type":"image/png","base64":"..."}}
```

代理不让客户端选择服务商/模型/费用参数。后端必须自行定义幂等/对账和错误映射；不要仅将公开 endpoint 当成不限额转发器。本包没有宣称此代理已经可访问。

`openai_provider.gd` 是用户自管**本地开发**协议适配路径，只有显式设置 `enable_direct_local_development=true` 并填入经部署确认的 `model` 后才编码。HTTP 凭证仍由可信运行环境另行注入；不要在公开终端启用直连或在代码里填真实密钥。测试使用已核官方模型名 `gpt-image-2` 仅验证序列化，不代表选定产品厂商或预算。

## 官方协议调研与验证范围

核验日期：2026-10-16。仅阅读公开官方页面；未登录、未查找/读取任何真实密钥、未查询账号可用模型、未上传或生成真实图片。

| 方案 | 本轮核验内容 | 实现状态 |
| --- | --- | --- |
| OpenAI Images Edit | `POST https://api.openai.com/v1/images/edits` 支持图片和提示词；JSON `images[].image_url` 支持 data URL；`n=1`、`output_format=png`；响应 `data[0].b64_json` | 已实现 JSON 单图适配器；固定 `1024x1024`、`quality=low`，模型显式配置。仅离线请求形状/响应 fixture 验证，未验证线上兼容性、账号权限、耗时、画质或收费 |
| Google Gemini | 官方 image editing 示例提供文本和 base64 图片；REST `POST https://generativelanguage.googleapis.com/v1beta/interactions`，示例模型 `gemini-nano-banana-2.1`，请求 `input` 文本/图片项，图片项 `mime_type`/`data`；认证 header `x-goog-api-key` | 可行替代调研；**未实现 Gemini 适配器**，没有凭记忆使用旧 `generateContent` 示例 |

官方来源：

- [OpenAI Create image edit API reference](https://developers.openai.com/api/reference/resources/images/methods/edit)（本包依据该页 JSON 参数，而非 multipart 示例；不要混用字段）
- [OpenAI Image generation guide](https://developers.openai.com/api/docs/guides/image-generation)
- [OpenAI API overview / authentication](https://developers.openai.com/api/reference/overview)
- [Google Gemini image generation / image editing](https://ai.google.dev/gemini-api/docs/image-generation#image_editing_text-and-image-to-image)
- [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html)

页面可能更新，真实接通前应复核选定模型与账户权限、价格、图片隐私/留存及所在网络可达性。ChatGPT 对话生图工具不属于用户应用的 API，本包没有使用它。

真实接通仍需：确认服务商和模型、展厅代理/本地开发部署方式、密钥的安全交接、后端授权与额度方案，以及真实调用/费用批准。完成这些决策之前，保持 mock，不填真实凭证。

## 文件清单

- `request.gd` / `result.gd` / `job.gd`：统一输入输出与任务句柄。
- `service.gd`：快照、校验、deadline、取消、一次完成与生命周期。
- `provider.gd` / `openai_provider.gd` / `proxy_provider.gd`：最小适配契约和两个协议边界。
- `codec.gd`：受限 PNG/base64/JSON 解码与固定错误映射。
- `ark_seedream_provider.gd` / `jpeg_codec.gd`：国内官方已核验模型 ID 注入，Pro 独立的 standard/2K/单图参数，兼容历史 PNG/JPEG 输出。
- `ark_http_transport.gd` / `ark_call_budget.gd`：唯一北京官方端点限制、共享单价/调用预留记录、10 元上限与未知价格阻断。
- `tests/image_generation/verify_ark_seedream.gd`：40 项完全离线的国内适配与预算验证。
- `http_transport.gd` / `mock_transport.gd`：默认拒绝联网的传输实现、完全离线模拟。
- `demo.gd` / `demo.tscn`：独立可运行验收界面。
- `README.md`：接口、安全边界与官方来源。
- `tests/image_generation/verify_image_generation.gd`：有限离线回归，合成输入，不使用真实图片或密钥。
- `tests/image_generation/verify_transport_lifecycle.gd`：注入同步 cancel 回调及无效工厂节点，验证防重入、完成信号顺序和节点所有权。
- `tests/image_generation/validation.json` / `mock_demo.png`：27/27 检查摘要及 Godot 自身视口捕获的模拟结果。

测试覆盖协议形状和业务边界，不能替代真实服务联调或实体展厅设备验收。没有安装软件，也没有修改工程配置、共享 README、桥、drawing 或 level。
