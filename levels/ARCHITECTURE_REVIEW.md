# 分层审查与有限清理

2026-10-16：保留已验收桥链路、完整国风桥插画及 project.godot；船仍禁用。本次未读取凭据、未连接 8769、未调用官方生图，未修改 image_generation/ 或 local_image_service/ 的并行工作。

## 结论

当前分层可以继续使用，没有发现阻断现有链路的越层依赖。核心包的字面资源引用扫描为 89 处、0 处违反本次检查规则；动态路径仍由标准阶段接口与运行测试约束，静态扫描不等于隔离沙箱或穷尽动态调用。

| 层 | 职责与依赖边界 |
| --- | --- |
| levels/level_flow | 生命周期、完成事件、结果与进度；工厂注入，不实现笔刷、模型规则或网络协议 |
| levels/model_stage、bridge_stage_adapter | 通用模型事件转发与桥旧场景薄封装；完成事实和 drawing_asset 独立，桥完成不意味着实时导出了模型图片 |
| content/luban_bridge、app/bridge_workshop | 模型几何、木材表现与装配规则；app 是桥组件内部的组合根，连接 session、操作及 UI |
| interaction、session | 通用手势/请求契约与本地进度；不导入具体桥包、绘画或图像生成 |
| drawing | 2D 素材、独立笔迹、撤销与全纸合成；不反向读取关卡进度、3D 模型或服务 |
| levels/drawing_stage、generation_stage | PNG 交接和窗口生命周期；风格提示词由关卡配置传入，复用独立组件，不复制画笔/供应商实现 |
| image_generation | Request/Job、输入快照、取消/超时和 provider/transport 契约；不导入关卡、绘画或模型包 |
| local_image_service | 当前关卡路径的 Key、Flash 选择、预算、去重、供应商协议与结果恢复；仅经原生 loopback HTTP 与 Godot 交接 |

图像包保留的直连 provider、proxy、mock、loopback 各有独立协议/测试用途；已验收关卡使用 loopback 持钥边界，没有据“默认不用”删除公共 provider。历史烘焙工具位于 levels/tools，是离线制作工具，不计入关卡运行依赖。

## 本轮改动

- 将已验收完整国风提示词从通用 generation_stage 移至 level_catalog 的 config.prompt，原文字节与真实验收保存的 submitted_prompt.txt 一致。适配器只保留通用缺省指令。
- 删除 drag_interaction.slots 未读取成员和 first_level 中无消费者的 asset_ref 字段；操作路径、装配动画、模型几何和已验收行为不变。
- 删除端到端测试已不用的 Window 参数；STUB 测试增加可选 headless，默认图形方式不变。失败等待返回布尔结果并提前记录报告，避免空结果访问掩盖原始错误。
- generation_handoff 的注释更新为实际宿主行为；LOCAL_GENERATION 删去“尚未发生真实请求”的过期说法，并明确四种模式及已有证据。历史烘焙说明缩为当前方案链接与复现入口。
- 保留最新版插画、原始/旧素材、历史验收记录、诊断入口及 .uid/.import 文件。它们有兼容、复现或 Godot 资源标识用途；未以未追踪状态作为删除依据。

## 有限风险与未扩大范围的事项

- level_flow 只为通用校验引用 level_catalog；示例配置也使用 first_level 的数组位置构建。扩展多关卡时可分离纯校验和阶段构建，本轮不增加管理层或重构已验收入口。
- server/recovery 在函数内部互相引用少量解码工具，存在轻度模块耦合；现有测试覆盖此路径，本轮未改并行服务代码。
- 绘画历史和 user:// 导出尚无自动留存上限。展机部署需确定历史/素材预算与用户作品保留策略；本轮不擅自截断撤销或删除作品。
- 本次图形验证使用 Godot 事件注入，生成按钮使用 pressed 信号；不宣称原生鼠标或实体触屏已验收。插画仍是已选风格化艺术候选，不宣称精确结构复原。

## 证据

- `tests/levels/cleanup_evidence/validation.json`：完整真实槽位装配、撤除、插画落纸、7 条指针笔迹、1920×1280 全纸导出、离线结果和返回保留，41 项通过；本轮 request_sent=false。
- `tests/levels/cleanup_stub_evidence/validation.json`：无窗口 STUB 35 项通过，包含打开不发、HTTP 原图像素往返、取消、模式不符拒绝及重置；official_calls=0、credential_reads=0，随机测试端口明确拒绝 8769。
- `tests/levels/cleanup_evidence/dependency_audit.json`：字面资源边界、服务内部静态导入、最新素材哈希及已验收提示词核对。辅助脚本只读取公开源码和验收产物，不执行服务代码。

STUB 最初在受限进程环境中未到达测试服务；使用当前公开服务代码、放开本机 HTTP 进程权限后通过。没有为修复测试而访问真实服务、读取 Key 或改动供应商实现。原真实 43 项验收及其输出继续保留在 art_bridge_flash_evidence/，不以本次离线结果替代。
