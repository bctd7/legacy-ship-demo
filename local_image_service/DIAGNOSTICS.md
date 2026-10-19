Latest live status (2026-10-16 10:57 UTC): the second explicitly authorized single request returned upstream HTTP 429 / `SetLimitExceeded` (local 502); no image was returned. Official request ID: `02179214825345768a4d5226e4976fceebdcfa7e5c0e722f7f208`. No retry was sent. Current service has real_calls=1 and inflight=false. The task preserves the first unknown 60-fen reservation plus this request's 60 fen: 120 fen conservatively reserved, actual billing unverified. See [second request evidence](../tests/image_generation/second_real_bridge/RESULT.md). The official error reference confirms a configured model/endpoint usage-limit rejection. Account-side investigation of Model Activation / Safe Experience Mode or endpoint limits is the current blocker; the exact limiting setting has not been confirmed. No account setting was changed. The older preparation/first-attempt notes below are historical, including the previous recommendation to restart with carry-forward: the user already restarted without carry and that was accepted for this authorized attempt.

# 首次 502 的诊断范围与安全错误接口

## 已确认的事实

首次且唯一一次授权真实联调于 `2026-10-16T10:39:01.429443+00:00` 开始，本机返回 HTTP 502 / `upstream_outcome_unknown`，耗时 1.213 秒，调用计数 0→1、预留 0→60 分，无图片返回。此前和本轮均没有重试；实际账户费用未知，60 分继续占用本轮 10 元的保守额度。

代码确认了**诊断信息丢失的根因**：旧 `Engine.generate()` 的 `except Exception` 将以下不同异常全部覆盖成同一错误，并丢弃具体分类：

- `opener.open()` 的 HTTPError（4xx/5xx/被拒绝的重定向）。
- URLError、DNS/TLS/连接错误与 socket 超时。
- 请求/认证头编码异常。
- 响应 JSON、结构、PNG 校验和体积上限错误。

这不是对**首次上游失败根因**的确定：旧进程既未保存上游 HTTP 状态、官方 code/request ID，也未记录原始异常。现有脱敏回执和已知本机日志不能恢复这些信息。1.213 秒没有达到配置的 120 秒 socket/150 秒客户端等待上限，但不能据此排除更早的连接层失败，也不能断言是 Key、模型未开通或参数错误。

用户提出“似乎模型没有开通”仍是待核验假设；没有首次真实返回的 `ModelNotOpen` 或 `OperationDenied.ServiceNotOpen` 等 code，不能据此确认为该原因。测试中的这些 code 均是人工模拟样例。

## 静态协议核对

已重新读取 [官方图片 API](https://docs.volcengine.com/docs/ark/image-generation-api?lang=zh)，代码中的北京官方 endpoint、Pro 单 PNG data URL、standard、2K、PNG/base64、水印、`layer_decomposition=false`，及省略 Pro 不支持的组图/stream 字段，与公开参数说明未见明显冲突。该判断不能证明账号权限、模型开通或运行中的真实凭证有效。

[官方错误码说明](https://ark.volcengine.com/region:cn-beijing/docs/error-codes)列出认证、模型未开通、参数、限流等不同代码；没有实际返回的状态/code 就不能选定其中某一个为首次根因。本轮仅访问公开文档，不登录账号或查询真实调用。

## 修复后的返回与保留字段

本机 HTTP 仍返回 502 / `upstream_outcome_unknown`，不改变未知结果及扣费语义；新增可选 `error.diagnostic`，并在认证后的 `/v1/status` 暴露同一白名单 `last_failure`：

```json
{
  "code": "upstream_outcome_unknown",
  "message": "Local image request did not complete.",
  "automatic_retry": false,
  "outcome_unknown": true,
  "diagnostic": {
    "category": "upstream_http",
    "upstream_http_status": 401,
    "vendor_code": "AuthenticationError",
    "upstream_request_id": "fixture-request-001"
  }
}
```

以上只是**无密钥模拟样例，不是首次真实请求的错误值**。Godot 在 `Result.error.diagnostic` 接收这些可选字段，并再次过滤；旧进程不含 diagnostic 的响应仍兼容。

分类白名单为 `upstream_http`、`network_timeout`、`network_tls`、`network_dns`、`network_connection`、`network_transport`、`request_encoding`、`response_json`、`response_schema`、`response_image`、`response_too_large`、`unexpected`。

只保留分类、100–599 整数状态码、长度受限的 ASCII `vendor_code` 和 `upstream_request_id`。官方错误体只限量读取 16 KiB：提取 `error.code`、结构化 request ID，或从 `error.message` 中提取严格限定的 Request ID token；不保留原消息。响应头仅读取 `x-request-id`/`x-tt-logid` 的相关 ID，不枚举/序列化 headers。控制字符、URL、超长值和凭证式前缀被丢弃。不会返回或记录原始 body、base64、认证头、会话令牌、异常文本、TLS 证书详情或 Key。

未知结果仍保留调用计数、预留金额和去重回执。重复同内容只返回已保存的白名单诊断，不再调用上游；超时不代表免计费，HTTP 401/4xx 也不会在未经对账时自动释放预留。

## 本轮验证

`test_upstream_errors.py` 使用 FakeOpener/FakeResponse，**没有 Key、没有套接字或真实服务请求**，覆盖 HTTPError、网络/编码错误、响应解析、字段脱敏、无重试及额度保留。`verify_loopback_diagnostics.gd` 仅解析模拟 JSON。既有 stub HTTP 回归使用随机 loopback 端口，完全不接触用户正在运行的 `8769` 服务。

测试结果见 `tests/image_generation/upstream_diagnostic_validation.json`。本轮新增真实生成请求为 0，既有 1 次/60 分预留不变。

## 用户最小下一步

1. **不用重发图**。用户可自行在火山官方控制台查看上述 UTC 时刻附近的调用/失败记录、Pro 开通状态与费用；按控制台时区换算时间。只需反馈上游 HTTP 状态、官方错误码、请求 ID 和已知费用，不提供 Key、认证头或原始响应。控制台未必显示未到达平台的网络失败，因此“无记录”也需谨慎解释。
2. 当前已运行服务没有热更新，首次分类已丢失；磁盘修复不能追溯恢复。**本轮不停止、不重启该进程，不要求用户现在重新输入 Key。**
3. 用户已确认“现在开通”，并授权修复后第二次单次联调；但当前旧服务已达 1 次上限，且不会热更新。只有用户准备好安全重输凭证后，才由用户手动 Ctrl+C 并运行 `.\local_image_service\start_official.ps1 -PriorReservedFen 60`。上限仍是 1 次，带入之前的 60 分；新进程 `/status`/ready 明示 `prior_reserved_fen:60`、`reserved_fen:60`、`real_calls:0`、`max_calls:1`。本轮没有执行重启或读取 Key。
4. 用户回报新 ready 后，才能核验状态并安排那一次已授权的新请求；当前不在旧代码/旧额度上盲测。新请求会将预留合计变为 120 分，实际费用仍待对账；出现超时/未知仍不得重试。不能将新进程 0 次计数当作本轮尚未消费。
