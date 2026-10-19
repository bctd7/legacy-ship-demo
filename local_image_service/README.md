# 本地图片生成服务

当前用户选择：**Seedream 5.0 Flash**。Python 标准库服务与 Godot/drawing/levels 独立，默认运行仍为离线 stub。未自动启动、开通账户或发送新生图请求。

## 当前型号与启动

| 配置 | 官方型号 | 已核公开单价 | 状态 |
| --- | --- | --- | --- |
| `flash`（默认） | `doubao-seedream-5-0-flash-260915` | 0.12 元/张 | 已通过离线协议验证，未真实调用 Flash，速度待实测 |
| `pro`（显式可选） | `doubao-seedream-5-0-pro-260628` | 本配置 2K / standard：0.60 元/张 | 第四次 Pro 请求已返回并验证真实图片 |

价格是 2026-10-16 查询的公开标价，实际账单与账户价格以官方控制台为准。用户此前提出 Lite，随后明确改选 Flash；本服务没有将 Lite 设为默认，也没有自动模型回退。官方型号列表仍将 Lite 标为「即将下线」，本轮停止 Lite 默认配置调查，未确认其具体下线日期。

## 临时本机 demo：只填一次，再双击

1. 将 `local_image_service/private/api_key.example.json` 复制为同目录的 **`api_key.local.json`**，由你自己把 `api_key` 的空字符串填成真实 Key。程序只提供空模板；本轮没有创建/读取/覆盖真实配置，也没有调用 Windows 凭据管理器。
2. 双击 **`local_image_service/start_image_service.vbs`**。以后继续双击此入口，不需要再执行命令或重复输入 Key。已开窗口会切回同一个实例；有兼容服务时直接连接。若 8769 上仍运行旧 PowerShell 服务，先在旧窗口停止一次，再点“启动 / 重新连接”。

这是用户指定的临时明文本机配置，不是系统保险库；仅用于受控本机。真实配置和 `private/results/` 均由本目录 `.gitignore` 排除；**整个 `local_image_service/` 还由 `.gdignore` 排除 Godot 导入和正常导出**。已经用独立假凭据项目实际导出 PCK（含 `include_filter="*"`），再在另一个干净项目挂载验证：公开对照文件存在，私有配置不存在；不是只检查 `.gitignore`。不要把真实配置加入 Git 或手工复制到分发目录。

默认 Flash 0.12 元/张。先在官方控制台确认 Flash 可用。双击只启动/连接本机服务，不发送图片，不注册系统自启动、不修改防火墙。界面显示调用和错误，Godot 的统一请求接口不变。

**不再默认每启动只允许一次。** 保持同一时间仅一个请求；普通重复点击会复用成功结果或提示仍在进行/结果未知，不会自动重发。失败请求需在服务窗口中选中后点击 **“手动重试（新计费请求）”**，每次明确点击最多发送一个新请求。已完成和未知尝试均保留历史；同一重试操作 ID 的重复传递不会再次调用。仍保留既有会话总额保护；这是次数统计/显式用户操作，不是无限自动重试。

成功响应及图片保存在本机 `local_image_service/private/results/`；“查看选中结果”会取回已有图片，不重新生成。解析失败的响应仍可用下文的离线恢复入口处理。关闭服务窗口会停止本次启动器自己的服务；进行中会阻止正常关闭，避免把等待取消误当成服务商停止计费。

可选终端开发入口仍保留 `start_official.ps1`（默认 Flash；显式 `-ModelProfile pro` 才用 Pro），默认也不再限制每次启动一张。日常直接双击即可。

独立无密钥 stub：`python .\local_image_service\server.py --mode stub --port 8769`。Godot `image_generation/loopback_demo.tscn` 默认 stub；真实服务模式仍须显式选择 official，启动场景本身不自动生成。

## 单图协议与安全边界

Flash 与 Pro 均使用官方北京 `https://ark.cn-beijing.volces.com/api/v3/images/generations`：一张 PNG data URL 加原始提示词，`size:2K`、`output_format:png`、`response_format:b64_json`、`watermark:true`、`layer_decomposition:false`、`optimize_prompt_options.mode:standard`。两者不支持组图或流式，省略 `sequential_image_generation` 和 `stream`；Flash 不配置不支持的 `fast` 模式。不下载返回 URL，不改账户或模型权限。

Godot 接口仍是 `service.generate(Request.new(image,prompt))`、`job.finished`、`job.cancel()`；Godot 不接触服务商 Key。`loopback_provider.gd` 及 `loopback_transport.gd` 只接入本机服务。原生会话鉴权仅驻内存；拒绝浏览器 Origin/Referer、LAN、重定向和任意 URL。

| 本机接口 | 功能 |
| --- | --- |
| `GET /v1/session` | 原生头 `X-Image-Client:godot-loopback-v1`，取得内存会话与模式 |
| `GET /v1/status` | 需 `X-Local-Session`，返回型号、计数、预留、在途和安全诊断，不返回 Key、图片或提示词 |
| `POST /v1/images/generate` | JSON v1：`schema_version,request_id,prompt,image:{mime_type:"image/png",base64}`，同一会话鉴权 |

仅监听 `127.0.0.1`；不是公开展厅长期凭证保管方案。展示客户端不得打包长期 Key，正式部署仍须受控的服务端边界。输入上限 8 MiB、15–4096 像素边、JSON/响应有界；同一时刻只发一个请求。不再有默认单次启动次数上限，但保持单请求并发，不自动重试。超时/取消不证明服务商停止计费；未知结果保留预留和去重记录，历史费用独立留在回执。

## 响应保留和离线恢复

请求明确协商 JSON、`Accept-Encoding:identity`，兼容有界 gzip/deflate 解压；br 不安装解码软件，返回明确的 `response_encoding`。JSON/BOM、Content-Type、长度和截断有固定分类。意外 SSE/HTML 不冒充成功。诊断只含枚举类型/编码/BOM/结构特征、字节长度、解析位置、状态和有限 ID；不输出正文片段、base64、请求头、异常原文或密钥。

收到有界 2xx 响应后，解析前把响应字节及白名单元数据保存在启动器的 `private/results/<recovery_id>/`（终端开发模式使用当前用户临时目录 `image-generation-recovery-<随机后缀>/<recovery_id>/`）；成功时同时保存 `image.png`。控制台只报告目录与恢复 ID，`/v1/status.last_response` 提供恢复引用。文件可能含生成图和模型返回的用户内容，应保留在受控账户本机，不上传原始响应或提交仓库。Windows 使用该用户临时目录继承的 ACL，不宣称 chmod 建立了新 ACL。磁盘失败会明确标记未保存。

使用控制台给出的实际目录与 ID 离线恢复（此命令不访问网络、不读取凭证）：

```powershell
python .\local_image_service\recovery.py --directory '实际恢复目录' --capture-id '实际32位恢复ID'
```

只解码已保存响应，输出至该恢复子目录 `image.png`。对无法恢复的截断/语法错误或未知 br 编码会返回明确失败，绝不重新生成。第三次响应当时未保存，不能追溯恢复，也不能因第四次成功就认定第三次根因。

## 离线验证与官方来源

`python -m unittest discover -s .\local_image_service -p 'test_*.py' -q`：85 项 Python 检查（合成响应、随机 loopback 端口 stub，真实服务商调用 0）。Godot `tests/image_generation/verify_ark_seedream.gd`：44 项检查。Flash 离线验证不等于账户已开通或真实延迟已经测得。

- [官方型号列表](https://ark.volcengine.com/region:cn-beijing/docs/model-list)：Flash ID 与单图图生图。
- [官方图片 API](https://ark.volcengine.com/region:cn-beijing/docs/image-generation-api)：Flash/Pro 参数、PNG/base64、非流式单图。
- [官方模型价格](https://ark.volcengine.com/region:cn-beijing/docs/model-pricing)：Flash 0.12 元/张及 Pro 像素档位价格。
- [第四次真实 Pro 结果](../tests/image_generation/fourth_real_bridge/RESULT.md)；[实际输入与提示词说明](../tests/image_generation/fourth_real_bridge/input_explanation.json)。

## 新的本机控制接口

新增接口同样要求原生头及本次会话鉴权：`GET /v1/operations` 仅列出操作 ID、状态和脱敏诊断；`GET /v1/results/<request_id>` 取回已有结果；`POST /v1/images/retry` 接收 `{request_id,retry_request_id,confirm_new_charge:true}`，只允许已结束的失败/未知请求，保存原回执并以新操作 ID 发一次。Godot 原有 `POST /v1/images/generate` 未改变。协议修订为 2，启动器不会接管旧版、Pro 或仍带单次上限的服务，也不会自动终止它们。
