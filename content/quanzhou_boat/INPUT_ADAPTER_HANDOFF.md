# 公共输入适配与主工程导入清单

已按主任务指定的稳定 `interaction/CONTRACT.md` 接入同一公共包。船内没有独立鼠标映射或平移/旋转计算副本；未来输入设备可提供同一公共命令结构，本轮未实现完整触摸。

## 实际接线

- 公共 `mouse_input_adapter.map_event()` 映射鼠标/Esc；公共 `gesture_router` 锁定 `part / rotate / pan / ui` 并校验匹配松开。船复用公共 `drag_interaction.handle_pointer()`、装配来源/释放契约、取消/失焦/退出清理。
- `boat_drag.gd` 只覆盖船的按下上下文：卡片作为世界区外的显式来源；当前可操作金色组按真实三角形命中并保存世界抓点；UI 上释放清空槽而拒绝提交。相机动作信号暂停近景自动返回。鼠标按钮映射留在公共包。
- 左键命中可操作件归拖件；左键视图空白或右键归旋转；中键平移；空闲且无遮挡的视图滚轮缩放。拥有者和按钮从按下到匹配松开不变；跨 UI 暂停相机但保留归属，第二按键/滚轮不能抢占。Esc、失焦和退出清理来源、预览与归属，迟到松开不安装。
- `boat_camera.gd` 仅保留船的缩放焦点和旧边界属性名适配。公共 `orbit_camera` 负责旋转、平移、缩放和复位。模型参数独立放在 `config/cameras.json`：整船 0.28–12m，平移相对模型初始中心半径最多 2m，垂直范围沿用公共约束 -2/3～4/3m；手动局部镜头 0.12–5m、平移上限 0.35m。没有复制桥的尺度。
- 公共平移体现在 `focus`，因此相机快照/插值和手动局部、自动装配近景返回都保留完整焦点、角度、距离与边界。显式视角复位和装配重置恢复模型初值。`cb73b3e` 的私有归一化 `pan_offset` 已移除。

## 可运行交付与导入

独立入口仍为 `res://content/quanzhou_boat/demo.tscn`；在此副本双击 `content/quanzhou_boat/run_demo.cmd`，或调用 `run_demo.ps1 -GodotExecutable '<Godot4.7.2.exe绝对路径>'`。Compatibility，未改默认项目入口。

主工程仅导入 **`content/quanzhou_boat/` 整包的最终快照**，不复制此副本的 `project.godot`、`levels/`、主流程、桥包、绘画、生图或 UI。只读阶段依赖仍为现有 `levels/stage.gd`；船的 `model.gd / stage_adapter.gd` 提供原有生命周期接口。主任务负责主工程关卡接线。

本副本为独立运行原样复制了用户授权的公共依赖，单独提交为 **`dd123f0`**。**主工程已有同一包，导入船时跳过该依赖同步提交，不覆盖其 `interaction/`**。实际依赖为 `drag_interaction.gd / drag_contract.gd / orbit_camera.gd / gesture_router.gd / mouse_input_adapter.gd`；来源与逐文件 SHA-256 见 `reference/shared_input_dependency.json`，复制内容与指定主项目逐字节一致。该依赖提交不含船逻辑，不构成另一套公共实现。

船保持 28 个局部操作组、59 个源根、1286 网格和 768 个贴面紧固件；原模型资源、分组与钉子拟合配置均未改。本轮未减模、未改几何和目标设备性能保证。截图/运行日志与方法边界见 `evidence/shared_input/README.md`、`evidence/shared_visual/README.md`。
