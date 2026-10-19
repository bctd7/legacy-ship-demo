# 独立关卡与整体演示

**本轮默认入口**为 `res://levels/integrated_demo.tscn`，或双击 `levels/run_demo.cmd`。默认流程只有关卡内的模型拼装 → 白纸绘画，本关模型为已验收的桥。桥完成后点击“进入下一阶段”，把一张模型 2D 占位图片拖入固定区域并自由绘画，点击“导出绘画并完成本阶段”即完成本轮。当前联通测试不要求船占位图片；额外模型拼装留在 disabled_stages，禁用。主入口未改，绘画独立验收入口保持原样。

通用配置支持可选附加素材：将场景 level_options 的 include_optional_materials 设为 true，可恢复原来的远小后层/近大前层构图；默认 false 只保留当前模型素材。该配置只按素材 optional 标记筛选，不按模型名称判断。占位图仍仅是示意，正式美术后置。模型与素材接口见 [MODEL_CONTRACT.md](MODEL_CONTRACT.md)。

绘画成功导出后显示离线 MOCK 与本机服务按钮，生图仍为可选步骤，不改变已完成的拼装与绘画进度。默认本机 STUB；真实模式须明确 official 启动并手动点击发送，不自动生成，不读取凭证，不在失败后降级。费用/取消边界、公开接口与启动步骤见 [本机生图接线](LOCAL_GENERATION.md)。重新开始会取消在途任务、失效旧回调并创建新的输出目录。

PowerShell 可传入本机已有 Godot 路径：`levels/run_demo.ps1 -GodotExecutable 完整路径`。脚本显式选择 integrated_demo 场景，不依赖编辑器当前标签，不下载或安装软件。

关卡外观通过 levels/presentation/ 注入，宿主面板/主题与模型规则、流程状态、绘画文档分离。共用绘画工具栏及本轮清理、1080p 运行检查和已知预算缺口见 [表现层说明](presentation/README.md)。

原来的 `res://levels/level_demo.tscn` 保留为三阶段契约诊断入口：它的正式模式仍在未接入阶段等待，顶部可选全 mock；该诊断入口不是本轮默认流程。

## 文件所有权

本实现仅新增 `levels/` 和 `tests/levels/`。不修改桥内部、`drawing/`、`image_generation/`、`project.godot` 或共享 README。已获协调线程确认这两个目录的独占所有权；先在 task-3 隔离副本验证，再复制新增文件。暂存与本地提交仅限这两个目录，保留 project.godot 的既存变更。

## 最小接口与结果

阶段是 `Control`，暴露 `enter_stage(config:Dictionary, context:Dictionary)->String`、`exit_stage()->void`、`stage_result(stage_id:String, result:Dictionary)`。进入返回空字符串表示成功，错误包含可定位原因；退出须停止输入和订阅。阶段继承 `stage.gd` 即可使用默认生命周期与结果封装。

结果为 `{schema:1, status:"completed"|"pending_integration"|"failed", payload:Dictionary, message:String, simulated:bool}`。只有当前阶段、当前进入周期、合法 completed 结果能进入进度。进入期间暂存事件，仅 enter_stage 成功后接收；进入失败会先失效令牌并丢弃该阶段结果，然后退出清理。结果保存一次，重复报告无效；退出阶段的迟到事件无效。mock 模式与结果的 simulated 必须一致，且全 mock 阶段的模拟图片不能进入真实图像服务交接。demonstration 标记当前混合演示，2D 占位与可选 mock 结果分别附带明确来源。

`level_flow.gd` 保存阶段索引和结果，提供 `start(level, host, factories, mock_mode=false)`、`advance()->String`、`can_advance()->bool`、`progress()->Dictionary`、`stop()`。宿主显式传入 component→Callable 工厂，无全局自动加载。完成事件只记录结果，用户点击“进入下一阶段”才切换；未完成禁止推进。下一阶段 context 含 level_id、历史 results 的深拷贝和 mock_mode。`progress()` 也是深拷贝；正式与 mock 每次重新开始均清空进度。失败进入停留在该阶段并显示错误，宿主可修复依赖后重新 start；不自动跳过、不持久化、不提供全能状态管理器。

## 配置与适配

`level_catalog.gd` 的 integrated_demo 定义当前两阶段配置；first_level 保留原三阶段诊断配置。素材纹理须显式提供 texture_path，也可从 result_stage 的 payload.drawing_asset.texture_path 取得，兼容原 payload.texture_path。装配完成不会自动产生图片：当前本关模型描述引用用户选定的完整透明国风桥插画（艺术候选，非精确复原）；可选船图片仍为占位。桥完成事件仍只负责完成事实，PNG 是独立模型素材引用。素材 layer 从小到大排序后传给绘画组件，即数组从底层到顶层；笔画仍由原组件绘在素材上方。

- `bridge_stage_adapter.gd` 把原 workshop 场景放进独立 SubViewport，订阅现有 session.changed，只在 view_state().finished 为真时报告 content_snapshot；不改桥交互或模型规则。
- `pending_stage.gd` 显示“船未接入”，只报告 pending_integration，没有完成按钮，正式流程到船时等待，不会显示整关完成。
- `model_stage.gd` 根据模型描述加载适配器脚本或契约场景，仅转发完成事件、稳定模型 ID 和 2D 素材引用。通用层无模型名称条件分支。
- `drawing_stage.gd` 动态加载原绘画 surface/config，调用 configure；通过现有公共属性和 document 方法组织工具栏。宿主调用 export_to(path)，当前配置要求素材已落位，且只有 PNG 导出成功才完成；之后冻结编辑，保持已导出结果一致。不含实时 3D。
- `mock_stage.gd` 明确显示测试占位，仅 mock_mode 可进入；用于替换任意阶段，测试不依赖船或绘画界面状态。
- `generation_handoff.gd` 的 prepare 仅校验交接描述符；`generation_stage.gd` 为可选窗口薄适配器，可注入既有包的离线 mock 或严格 loopback transport。应用宿主取消/关闭/重置时失效请求序号，旧任务结果不能保存文件或覆盖界面；真实凭证与服务端预算不进入关卡层。

## 有限验证

在项目目录运行 Godot 4.7.2：

```powershell
& $godot --headless --path $project --script res://tests/levels/verify_level_flow.gd -- $pngOutput
```

41 项契约检查覆盖原有推进边界，并补充“进入期间完成后返回错误”和失败清理/迟到信号的原子性检查。真实桥使用合法 completed snapshot 验证 session 事件适配，不替代已验收的桥交互测试。失败导出检查会有一条预期的 Godot PNG 写入失败诊断。

去掉 `--headless` 并在 $pngOutput 后追加截图路径可保存独立 mock 演示截图，以及同目录 real_bridge_demo.png（额外 3 项，含界面各行无重叠检查）。实际鼠标/触屏操作仍需现场验收；没有复验桥内部或声明船可玩。

本轮整体入口验证运行 `--scene res://tests/levels/verify_integrated_entry.tscn -- 可写证据目录`，可加 --headless。它继承真实入口，不手动实例化演示或设置根窗口尺寸；验证桥完成到绘画、真实指针素材拖放/笔画、导出、重置，以及独立假模型的契约替换。附带可选 mock 的取消/失败/超时/重试和重置迟到回调检查。图形模式保存截图与 JSON；日志和截图位于 tests/levels/integrated_evidence/。

2026-10-16 实测：共享项目契约 41/41，普通入口无界面流程 40/40，隔离副本图形流程含截图 47/47；明确启动脚本运行 5 帧正常退出。入口测试对本关桥使用合法完成快照，不重验既有桥拼装动作；纸面拖放/笔画用真实 Godot 指针事件注入，可选窗口按钮用 pressed 信号触发。实体展厅鼠标与触屏留待现场验收。


## 本轮双模型接入更新

当前 `integrated_demo.tscn` 通过 `model_registry.gd` 配置桥→船→绘画；旧桥单模型验收使用 `--bridge-only` / `bridge_only` 配置。认可船图及最终船包dc59e9d已接入，实际完整流程与可见检查已完成，原生鼠标与保留项见最终交接。注册接口、完整入口、测试边界与交付依赖见 [BOAT_INTEGRATION_HANDOFF.md](BOAT_INTEGRATION_HANDOFF.md)。本节更新优先于上文旧的默认单模型/船占位说明。
