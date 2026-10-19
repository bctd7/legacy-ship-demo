# 独立绘画组件

入口：`res://drawing/drawing_demo.tscn`，Godot 中选中场景按 F6；或用已安装 Godot 控制台执行 `--path 项目目录 res://drawing/drawing_demo.tscn`。不依赖项目主场景。演示素材为程序生成的十字和圆形，**不是桥或船的正式素材**。

直接验收可双击 `drawing/run_demo.cmd`，它会显式启动绘画场景，不依赖编辑器当前标签。默认使用本机已安装的 Godot 4.7.2，其他路径用 `run_demo.ps1 -GodotExecutable 完整路径` 指定；不下载或安装。绘画窗口标题含 `drawing_demo.tscn`。编辑器方式需要先双击该 `.tscn`，确认顶部场景标签为 `drawing_demo` 再 F6：F6 运行当前场景标签，既存 `scenes/main.tscn` 是空 Node3D，运行它会显示灰色窗口。主入口 `project.godot` 和桥入口保持原样。

## 文件与接口

- `drawing_config.gd`：Resource 配置与校验。`paper_size` 是逻辑纸面像素（默认 960×640）。每个素材传 `id`、`label`、透明底 `texture:Texture2D`、`target_position:Vector2`、`display_size:Vector2`、`allowed_drop_rect:Rect2`、`lock_on_place:bool`，可选 `initially_locked:bool`。
- 坐标和尺寸归一化到纸面；目标位置是素材中心，`display_size` 是保留纹理比例的最大包围框。允许区域按拖动中心判断，落下后吸附配置中心，整个吸附包围框必须在纸内。默认松手后锁定；`initially_locked` 会预先放置并锁定素材。
- `drawing_surface.gd`：Control。`configure(config)->String` 返回空字符串表示成功；`document` 持有绘画数据；`brush_color`、`brush_width`（逻辑像素）、`eraser` 控制笔；`cancel_gesture()` 取消未提交手势。`material_placed(id, locked)` 和 `document_changed` 供宿主订阅。宿主自行组织工具栏和阶段按钮。
- 自绘外观可通过标准 Theme 的 DrawingSurface 类型令牌注入：paper/material_card/material_card_placed 样式盒，目标区/素材文字颜色、独立状态行和预览透明度。未注入时保留默认表现。只影响 _draw，白纸、素材、笔画和导出数据语义不随主题变化，不需要继承或读取私有手势状态。
- `drawing_document.gd`：RefCounted。白纸、素材占位、透明笔画独立。`undo()/redo()` 只操作笔画（包括橡皮和一次清空）；`clear_strokes(true)` 才清空，宿主必须先显示确认。`compose(size)` 返回 Image；`export_png(path,size)->Error` 只合成纸面，失败返回错误。输出默认逻辑尺寸，也允许同比例 16–4096 像素尺寸，拒绝比例失真。
- `drawing_toolbar.gd`：可复用 Control 工具栏，只调用 surface/document 公开操作，并订阅 document_changed 刷新撤销/重做状态。configure(surface, options) 构建一次；clear_requested 交给宿主显示确认，set_locked(true) 冻结已完成阶段的工具。独立演示与关卡宿主共用，不读取模型或关卡状态。
- `drawing_demo.gd/.tscn`：独立演示宿主，负责清空确认与 PNG 保存对话框；保留独立入口与既有操作语义。不包含模型或流程判断。

按下素材不会放置；移动至少 8 个界面单位并松手才提交。非法松手返回素材栏；移动已放置但未锁定的素材失败时保留原位。Esc、失焦、尺寸变化、隐藏、触摸取消撤销未提交手势。单个手势捕获一个指针，忽略其他触点及触摸模拟鼠标。笔画出纸边缘即结束；返回纸面需重新按下。素材层永远不参与橡皮处理。

## 验证

`--headless --path 项目目录 --script res://tests/drawing/verify_drawing.gd -- 可写PNG完整路径`

可去掉 `--headless` 并在 PNG 路径后再传一个截图路径，额外保存 Godot 实际渲染的演示界面。41 项无界面检查；带界面截图时 42 项。覆盖拖入/越界/取消/锁定、画笔/橡皮/撤销/确认清空、分辨率/比例/PNG 图层、单指捕获与触摸取消。使用 Godot 输入事件注入，实体鼠标、触摸屏和现场性能尚未正式验收；没有全量压力测试或软件安装。

启动回归：直接运行普通 `drawing_demo.tscn` 并用 Godot 的 `--write-movie 可写路径.png --quit-after 5` 捕获真实启动画面；补充运行 `res://tests/drawing/verify_entry_scene.tscn`，它继承原场景并用一个子节点检查默认视口布局、拖放、作画和工具按钮，不设置根窗口尺寸、不手动实例化演示。两条入口与旧 SceneTree 检查分开覆盖。

## 关卡层对接现状

当前入口为 `res://levels/integrated_demo.tscn`（或 levels/run_demo.cmd），默认拼装 → 绘画，额外模型拼装阶段当前禁用。宿主通过配置提供透明 2D 图片、固定区域、尺寸与层级；通用绘画不挂可操作 3D 模型，也不读取关卡进度。

流程与结果接口见 [关卡契约](../levels/CONTRACT.md)，新增任意模型所需描述、适配器和 2D 素材见 [模型契约](../levels/MODEL_CONTRACT.md)。本关通过 Theme 注入表现，白纸和导出图像仍由 drawing_document 决定。绘画独立入口不依赖 levels 或生图包。
