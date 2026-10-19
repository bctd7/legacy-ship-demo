# 绘画到本机图像服务

当前默认为桥拼装 → 完整透明桥插画放入白纸 → 自由绘画 → 1920×1280 全纸导出。船未接入，默认不要求船素材。当前素材及艺术准确性说明见 [ART_BRIDGE_HANDOFF.md](ART_BRIDGE_HANDOFF.md)。

## 启动与发送

- `levels/run_demo.cmd` 默认本机按钮为 STUB，非真实 AI。
- 用户自行启动已有本机服务后，用 `levels/run_local.ps1 -Mode official` 显式开启真实入口。可用 `-Port` 指定端口；脚本不启动服务、不读取 Key、不发送图片。
- 完成模型和绘画导出，点击“本机服务：真实生成”只打开面板。检查本次画布和提示词后，点击提交才产生 job。
- 只有 explicit official 启动启用真实发送；不会探测服务存在后自行升级为 official，也不会在失败后降级到 mock。

| 模式 | 来源 | 发送路径 |
| --- | --- | --- |
| offline_mock | 提示词哈希着色，非 AI | MockTransport，无网络 |
| local_stub | 完整绘画 PNG 原图回传，非 AI | 原生 loopback HTTP |
| local_official | 经过包校验的 official 回执 | 原生 loopback HTTP，由独立本机服务调用供应商 |
| recorded_replay | 已有结果回放，非本轮新生成 | 读取配置图片，不创建网络服务 |

## 分层与生命周期

关卡只使用 Service/Request/Job、LoopbackProvider(port,expected_mode) 与 LoopbackTransport，不读取 Key、不选择供应商模型或价格。127.0.0.1 限制、原生握手、来源校验、预算和去重归既有包/本机服务负责。国风提示词属于 `level_catalog.gd` 的关卡配置，经 config.prompt 传入通用生成适配器；用户仍可编辑。

打开面板不发送；等待时禁止重复提交。关闭/取消/重置会终止本地等待并失效请求序号，迟到结果不能保存或覆盖界面。真实服务可能继续处理或计费，不能把客户端取消当作退款或远端取消。手动再次提交仍受服务端去重约束；独立服务的已有回执/重试操作见 [服务说明](../local_image_service/README.md)。关卡不自动重试。

## 已有证据与安全回归

- 真实桥全链路已验收：43/43；20 件真实 Godot 拖放装配、撤除、插画落纸、7 条指针笔画、完整画布、单次 Flash 及实际结果显示。总计 53.608 秒，提交至保存/显示 25.917 秒；服务计数 1→2，本轮增量 1，无重试。记录在 `tests/levels/art_bridge_flash_evidence/`，清理与文档不再触发真实请求。
- 生成按钮使用 Button.pressed 信号，其余装配/绘画/导航使用 Godot 指针事件；未宣称原生鼠标或触屏验收。
- 离线完整流程：运行 `tests/levels/verify_art_bridge_e2e.tscn`，不传 `--one-real-flash`，不需要本机服务。
- STUB 回归：`python tests/levels/verify_local_level.py --godot <控制台程序> --project-root . --evidence-dir <可写目录>`。只创建并关闭随机端口的自有 STUB，明确拒绝 8769；验证打开不发、像素往返、取消、模式不匹配和重置。official 界面测试只对已知 STUB 握手，供应商调用为 0。
