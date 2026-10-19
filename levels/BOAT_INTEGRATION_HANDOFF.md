# 桥 → 船 → 绘画最终集成交接

主项目已导入固定船提交 `dc59e9d6127ab8a9e4268dbf9b196419fa9ccb8c` 的 `content/quanzhou_boat/`（343个源文件）。主项目 `interaction/` 和 `project.godot` 保持导入前哈希，未复制依赖提交 dd123f0，未写源副本。

入口：`res://levels/integrated_demo.tscn`。桥20件+辅助撤除 → 船28组自然动画 → 双素材绘画 → 完整1920×1280 PNG → 本机HTTP STUB结果及返回。`--bridge-only`保留旧桥单独回归。工程默认入口未改，录屏应显式运行此场景。

手动试玩/录屏并带隔离STUB（不会自动装配或绘画，关窗后服务退出）：

```powershell
python levels/run_recording_stub.py --godot 'C:/Users/USER/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe'
```

模型通过注册表/配置进入通用model工厂。`canvas_size`可指定模型自己的设计画布，宿主等比适配并由子视口自动转换输入；船使用1400×900，解决长说明面板压到托盘的问题。`compact_header`按阶段配置，不按模型名判断；桥保留原已验收视口比例。绘画document变化会清除已失效的“缺素材”提示。未改桥、船或绘画内部与公共操作包。

真实测试：完整无界面191/191；最终唯一可见窗口298/298（包含28组自然动画、每组面板边界、原始几何位置和临时效果清理）；最终通用替换34/34，桥兼容/取消/晚到回调40/40。STUB每次成功验证实际调用1次，官方调用/费用0，凭据读取0。最终18张阶段渲染截图均逐张查看，另查看实际OS窗口截图；实际渲染1680×1080，不能冒称目标机性能或严格1920物理屏幕验收。

证据：`tests/levels/boat_integration_evidence/final_visible/recording_validation.json`、`real_flow.json`、`visible_review.json`、`final_import.json`。整纸导出为 `final_visible/real_drawing.png`，STUB回传为 `stub_result.png`。

53项逐项结果见 [RECORDING_RESULTS.md](RECORDING_RESULTS.md) 和 `recording_acceptance.json`，没有把保留项改成通过。原生鼠标因工具缺失未验；部分相机/撤回/剖切旁路仅有船交付包406项证据，本轮没有在主项目全组合重跑；画笔全部工具、不可写导出、同进程第二遍全链路和目标机长时性能仍保留。官方模型结果未重跑。

自动验证进程及其STUB服务均已退出；现另留普通手动试玩窗口PID43020在0/3桥初态，隔离STUB由启动器PID44164维持并随关窗退出。用户原编辑器PID3408未动。未推送、未广泛暂存，未提交本轮大量无关脏改动。
