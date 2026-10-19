# 主场景直接启动验收（2026-10-16）

在实际项目根目录执行，Godot 4.7.2 / OpenGL Compatibility / 1400×900：

```powershell
# 普通直接启动；不带 --script，不改 project.godot；本次运行30帧后退出。
& $GodotConsole --path . res://image_generation/demo.tscn --quit-after 30 --log-file $OrdinaryLog

# 同一主场景由引擎直接加载；被动 SceneTree 驱动只检查现有 current_scene 并注入鼠标事件。
& $GodotConsole --path . res://image_generation/demo.tscn --script res://tests/image_generation/verify_direct_demo.gd --log-file $ClickLog -- "--evidence-dir=$EvidenceDir"
```

`$EvidenceDir` 须为已经存在的可写目录。验证脚本没有实例化或加载 demo 节点，不直接调用 `_generate()`；使用 `Input.parse_input_event` 的鼠标按下/松开触发按钮。

结果：普通启动 exit 0，日志无 ERROR/SCRIPT ERROR；主场景点击验收 10/10、exit 0。输入图、提示词、操作按钮正常可见，默认 mock 点击后显示结果图，取消按钮返回 `cancelled`。已人工读取三张真实 Godot 视口截图确认界面；没有复现整屏灰屏。

- `ordinary_direct_demo.log`：不带测试脚本的普通启动日志。
- `direct_demo.log` / `direct_demo_validation.json`：直接主场景点击验收日志与摘要。
- `direct_demo_initial.png`：初始界面，左侧合成输入图，右侧输出区等待生成。
- `direct_demo_success.png`：点击默认 mock 后的模拟结果。
- `direct_demo_cancel.png`：点击取消后的状态。

这不是实体鼠标/展厅硬件验收，也没有操作编辑器 F6 键；验证的是与 F6 同一场景资源的直接运行。全程使用合成图片与离线 mock，无凭证、上传或真实 API 调用。原 demo.gd、demo.tscn 和 project.godot 没有修改；未暂存或提交 Git。
