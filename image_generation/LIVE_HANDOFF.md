Current selection (2026-10-16): the user superseded Lite with **Seedream 5.0 Flash**. Default official service profile and direct adapter selection now use `doubao-seedream-5-0-flash-260915`, public price 12 fen/image. Pro is an explicit optional profile (60 fen for configured standard 2K). Network remains disabled by default; no real Flash request was sent. Restart the user-managed service with the unchanged `start_official.ps1` entry to load Flash after confirming its account activation. Do not silently reuse an old Pro process. See [current service configuration and recovery](../local_image_service/README.md). The fourth authorized Pro request already returned a verified 2368x1776 PNG in 39.876 seconds; older attempt/preparation notes below are historical. The third lost response's cause remains unproven.

Latest live status (2026-10-16 10:57 UTC): the second explicitly authorized single request returned upstream HTTP 429 / `SetLimitExceeded` (local 502); no image was returned. Official request ID: `02179214825345768a4d5226e4976fceebdcfa7e5c0e722f7f208`. No retry was sent. Current service has real_calls=1 and inflight=false. The task preserves the first unknown 60-fen reservation plus this request's 60 fen: 120 fen conservatively reserved, actual billing unverified. See [second request evidence](../tests/image_generation/second_real_bridge/RESULT.md). The official error reference confirms a configured model/endpoint usage-limit rejection. Account-side investigation of Model Activation / Safe Experience Mode or endpoint limits is the current blocker; the exact limiting setting has not been confirmed. No account setting was changed. The older preparation/first-attempt notes below are historical, including the previous recommendation to restart with carry-forward: the user already restarted without carry and that was accepted for this authorized attempt.

# 国内官方真实生成交接（2026-10-16）

最新状态：首次授权真实请求已执行，502 / `upstream_outcome_unknown`，无图片返回；现有回执不足以确定根因，不能把“可能没开通”当作已证实。此前 60 分预留继续计入 10 元，账户实际费用未知。本轮增加安全诊断但不重试、不重启用户服务。加载修复的用户步骤与 `-PriorReservedFen 60` 见 [DIAGNOSTICS.md](../local_image_service/DIAGNOSTICS.md)，下文“真实调用0”均为首次联调前的历史准备状态。

更新：同机轻量服务与严格 loopback 适配已实现，见 [服务启动／安全配置／接口](../local_image_service/README.md)。`start_official.ps1` 是已存在的用户手动隐藏输入入口，仅启动不会发出生成请求。本轮只运行无密钥 stub 的真实 HTTP 联通，官方调用 0；下文早期“尚未部署”的提案指正式展厅部署，已由这次独立 loopback 实现补足开发联通部分。

当前用户限定国内厂商官方 API，禁止国外服务和第三方中转。用户最终选择质量优先的 Seedream 5.0 Pro，本轮人民币 10 元预算及首次桥绘画单图联调已批准。同机服务的 stub 联通已完成，用户尚需自行配置安全凭证并确认 Pro 模型开通；有火山账号不代表 Pro 已开通。**真实调用 0 次，尚无真实生成成功证据。** provider 模型默认为空，只由可信宿主显式注入，不自动切换。既有 OpenAI、Gemini、4.5/Lite 调研和 proxy 方案为历史内容，不作为当前真实路由。

## 已核验协议

- 官方北京端点：`https://ark.cn-beijing.volces.com/api/v3/images/generations`。
- 当前型号 ID：`doubao-seedream-5-0-pro-260628`，以 `Ark.MODEL_PRO` 提供给宿主。历史已核验 4.5/Lite profile 仍可用于离线回归，不默认使用，不猜测未知 ID。
- Pro 请求：单张 PNG data URL + prompt、`size=2K`、`optimize_prompt_options.mode=standard`、`layer_decomposition=false`、`output_format=png`、`response_format=b64_json`，保留 AI 水印。
- Pro 不支持组图与流式输出，因此不发送 `sequential_image_generation`、`stream` 或 `n`；单图由 Pro 本身的接口能力保证。它支持 PNG/JPEG 格式，当前明确选择 PNG；不会沿用 4.5 的固定 JPEG 限制。返回统一 `Result.image`。

资料范围：已成功读取官方 API 对 Pro 的参数说明和模型列表中的精确 ID；给定 Pro 专页本轮多次读取超时。历史 4.5/Lite 在此前成功读取的列表中均标注“即将下线”，不能将它们误当当前选择。当前由协调会话提供的官方公开档价是 >261 万像素 0.60 元/张、首张参考输入免费；本会话没有读取账号实际价格，真实启用前仍需确认无额外费用。

来源：[官方 API](https://docs.volcengine.com/docs/ark/image-generation-api?lang=zh)、[官方创作教程](https://ark.volcengine.com/region:cn-beijing/docs/seedream-4-0-5-0)、[官方模型列表](https://ark.volcengine.com/region:cn-beijing/docs/model-list)、[官方端点及鉴权](https://ark.volcengine.com/region:cn-beijing/docs/base-url-and-authentication)。[Pro 专页](https://docs.volcengine.com/docs/ark/seedream-5-0-pro?lang=zh)为后续账号/价格复核入口，不宣称本轮已成功读取。

## 包内接线（未执行真实请求）

`ark_seedream_provider.gd` 只负责编解码，默认禁用且模型为空；由可信启动层显式注入已核验 ID。`ark_http_transport.gd` 只接受上述唯一官方端点，并复用默认关闭的 HTTP 传输。没有安装 SDK，没有获取/保存秘密的函数，没有第三方下载或备用路由。每个运行中的 service 使用固定配置的 provider，不在未完成请求期间更改型号。

可信宿主的配置入口：

```gdscript
const Service = preload("res://image_generation/service.gd")
const Ark = preload("res://image_generation/ark_seedream_provider.gd")
const Transport = preload("res://image_generation/ark_http_transport.gd")
const Budget = preload("res://image_generation/ark_call_budget.gd")

# 不获取密钥，不产生请求；默认阻止网络。
func prepare_ark(verified_model_id: String, session_headers: Callable, confirmed_unit_price_fen: int = 0,
        safe_setup_and_image_approved: bool = false) -> Node:
    var service = Service.new()
    var provider = Ark.new()
    provider.enable_direct_local_development = true
    provider.model = verified_model_id # 仅经用户确认的版本；默认不代选。
    service.provider = provider
    var budget = Budget.new() # 工厂创建的所有 job 共用一个预算对象。
    budget.unit_price_fen = confirmed_unit_price_fen
    budget.max_calls = 1 # 首轮单次验证；后续确认再增加，始终不超过16。
    budget.generation_authorized = safe_setup_and_image_approved
    service.transport_factory = func():
        var transport = Transport.new()
        transport.enabled = safe_setup_and_image_approved
        transport.allowed_urls = PackedStringArray([Ark.ENDPOINT])
        transport.transient_headers = session_headers
        transport.budget = budget
        return transport
    return service
```

宿主 add_child 后，继续使用 `service.generate(Request.new(用户绘画图片, 提示词))`、`job.finished` 和 `job.cancel()`。本轮只允许用户绘画的桥/船测试图与提示词用于后续真实验证；当前离线测试用代码合成图片，未传输这些用户图片。

## 用户自行安全配置的最小路径

1. 用户自行进入官方方舟控制台，确认账户、模型可用和实际单图价格。不要在聊天中贴密钥，不把密钥写入项目、资源、环境配置文件、截图或日志。
2. 在开发者受控电脑，通过后续宿主的一次性密码输入界面将认证保留在当前进程内存，交给 `transient_headers` 回调；退出后清空。当前包只提供回调接口，尚未实现或运行凭证输入流程，也未读取现有文件/环境秘密。
3. 宿主确认测试图传输授权、配置完成与已知价格后才解除发送开关。公开展厅电脑不得持有服务商长期密钥；公开部署方式仍是单独决策，当前不建立代理或中转。
4. 首次只发一张经确认的桥/船绘画及提示词；先核对账单与结果，再决定下一次请求。真实入口与 mock 显著分开，不能失败后自动改用 mock 伪装成功。

## 本机轻量服务的最小边界

Godot 保留统一 `Request(Image, prompt)` / `Result(Image, error)` 和 job 的 timeout/cancel；宿主注入新的本机 provider/transport 即可，绘画与关卡不需要知道服务商密钥。用户的十代 i5 / 8GB / Win10 / 1080p 主机若采用此方案，本机仅处理 JSON/图片与云端请求，不在本地运行生图模型；具体性能和录制流畅度仍需该设备实测。

- 已实现的本机服务只绑定 `127.0.0.1`，使用本次进程随机会话授权、请求体上限和单请求串行控制；不监听 `0.0.0.0`，不提供目录读取或任意 URL 转发功能。
- 最小本机数据协议可沿用项目 v1 的 `{schema_version:1,prompt,image:{mime_type:"image/png",base64}}` 和同形单图 PNG 响应；若上游为 JPEG，由本机转换为 PNG。接口不收服务商密钥、任意文件路径、任意模型或任意外部 endpoint。
- 真实模式配置后，服务进程持有运行时凭证、已确认型号/单价和共享预算账本，唯一外部请求直达北京官方端点。Godot 仅持有本机会话授权。这是独立同机边界，不是第三方中转站；本轮只验证 stub，正式展厅长期部署仍待另行验收。
- 原 `proxy_provider.gd` / `http_transport.gd` 继续严格要求 HTTPS；新 `loopback_provider.gd` / `loopback_transport.gd` 仅允许精确 `127.0.0.1` endpoint，不放宽通用校验。已运行的测试服务只用随机 loopback 端口并全部关闭，未开 LAN/公网、改防火墙/自启动或配置真实凭证。
- 连接取消/本地超时不代表方舟停止计费。本机端保留已发送调用的预算预留并去重/对账；客户端不自动重发。最小同步请求返回即可，不先增加队列、模型管理器或其他依赖。

## 预算、单价与调用记录

`ark_call_budget.gd` 默认 `generation_authorized=false`、`unit_price_fen=0`，任一未确认就拒绝。确认当前 Pro 2K 单图档完整费用为 0.60 元后，由可信宿主填入 60 分。当前总上限 1000 分、最多 16 次（16×60=960 分，17 次为 1020 分被拒绝）；首轮示例进一步限为 1 次。单价按已核实完整费用上界向上取整，费用不能确定就停。该类 `audit()` 返回调用数、预留金额、已配置单价、次数上限和逐条状态，不含图片、提示词或秘密，可由宿主安全展示/保存。

每次发送前预留一张的费用，同一 service 的所有传输共享预算；仅传输明确未发出时释放。发出后的失败、超时、取消仍保留额度，直到人工对账，防止重复计费。`audit()` 是本进程的保守预留记录，不是实际账单，也不能强制平台计费；重新启动前必须人工接续本轮累计消费，不能用进程重启重置 10 元额度。价格或费用范围无法确定时先停。

## 等待、结果与失败状态

现有统一 API 已支持 PNG 输入、JPEG 返回为 Image、等待、超时、取消与结构化错误。非流式接口等待最终响应；所读官方 API 没有给出可设置的服务端 deadline 或取消计费保证。因此 Request 超时仅为本地等待时限（包默认 60 秒，允许至 600 秒），不承诺服务端终止或免计费，也不自动重试。

调用方等待期间禁用重复提交，使用已有 epoch/token 忽略过期结果；新请求清空旧输出。成功只依据真实路由的结果，不把离线 fixture 或 mock 标成真实成功。取消、超时、限流、未授权、网络和解码错误必须明确显示；`outcome_unknown` 提示远端结果/费用待核对。

当前独立 demo 和 levels 可选入口仍是 mock；本轮不改 levels。真实模式接线和录制验收由维护该层的会话在安全配置完成后处理。

## 验证范围

`tests/image_generation/verify_ark_seedream.gd` 为合成图片、注入传输和预算测试，共 40 项，不获取凭证、不联网。Pro 的 standard/2K/单参考图参数与不支持字段省略、模型 ID 注入/固定端点、分型号 PNG/JPEG 解码、错误脱敏、禁第三方路由、未知单价阻断、0.60 元档最多16次和首轮单次限制均覆盖。它不能证明账户可用、实际画质、线上时延、账户价格或真实计费。
