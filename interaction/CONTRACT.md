# 拖动与装配数据约定

`drag_contract.gd` 只复制输入上下文及组装请求，不判断库存、兼容或依赖。

| 数据 | 含义与归属 |
| --- | --- |
| `selection.item_id` | 当前托盘项：库存类型、库存操作类别ID（如统一桥面`deck`），或辅助撤除动作 ID；不是模型网格名 |
| `selection.origin_slot` | 选中时的初始交互参考，使用副本；不随悬停覆盖 |
| `drag_source` | 按下时复制的 `item_id / origin_slot / gesture / candidates / eligible / revision / grab_id`，松手或取消前不改身份 |
| `hover_target` | 当前候选槽位，含 `id / anchor_m / radius_m / compatible / allowed / reason` 等；`trigger_point_m/trigger_index`指向本次触发位置；其中 `part_id` 仅是目标内容件，不是库存身份 |
| `slot.trigger_points_m` | 一个最终槽位可有多个触发位置；`anchor_m`最终参考和库存占用身份不变，各点共用同一半径 |
| 放置请求 | `inventory_type_id / slot_id / release_m / expected_revision`；由来源和目标分别填入 |
| 撤除请求 | `action_id / gesture_kind / grab_id / axis_distance_m / lateral_distance_m / expected_revision`；按钮与拖动都进入同一会话验证 |
| 会话正式状态 | `placements: slot_id -> 实际inventory_type_id` 与完成动作；操作类别不进入存档，剩余库存由占用推算，不另建计数 |
| 呈现状态 | 单一固定来源预览绕几何中心旋转，桥面仅显示共同板面；按住时中心跟随鼠标平面，候选只影响朝向；合法松手后才选择真实托臂支脚并开始原安装路径，不保存预览交接快照 |

内容规则将操作类别与目标解析为实际类型，再检查兼容、占用、依赖和数量；会话检查忙碌及版本，动画结束才提交。外部使用 `is_busy()`、`is_action_pending()`、`pending_ticket()` 查询，不读取 `_pending.commit`。根脚本只在 `_refresh_interaction()` 统一计算交互可用状态。

## 公共输入与视角操作接口

现有公共操作包目录为 `interaction/`。本包不依赖具体桥、船、绘画或生图模块；模型通过命中、可操作性和 UI 遮挡上下文接入。

- `mouse_input_adapter.gd`：`map_event(InputEvent)->Dictionary`。只把鼠标/键盘映射为 `phase:begin|move|end|zoom|cancel`、`intent:primary|rotate|pan`、`contact`、`position`、`delta`、`factor`。忽略触摸事件，未声称已实现触控。未来输入适配只需提供同一命令结构。
- `gesture_router.gd`：`begin(contact:String,intent:String,context:Dictionary)->String`，锁定 `part|rotate|pan|ui`；`release(contact)->String` 仅匹配来源才释放，`cancel()` 清空。`owner/contact` 用于读取当前归属。`camera_motion_allowed(context)->bool` 统一限制视角移动区域。
- context 字段：`inside_world`（3D 操作区）、`blocked`（可见 UI/模态）、`camera_enabled`、`part_hit`、`part_operable`。UI 优先；primary 命中可操作件优先归 part；否则 3D 空白归 rotate；中键 pan、右键 rotate。命中不可操作件不启动拖件。托盘作为显式可操作来源可在世界区域之外。
- 按下即锁定；第二按键不能抢占，错误松开不能释放。视角捕获后移到 UI 或 3D 区外暂停相机，仍保留归属直到匹配松开；不能在中途变成零件拖动或 UI 点击。滚轮仅在空闲、3D 区且无 UI 遮挡时缩放。
- `orbit_camera.gd`：`rotate_view(delta)`、`pan_view(delta,viewport_size)`、`zoom(factor)`、`reset_view()`。构造 `new(camera,settings={})` 可配置 `focus/yaw/pitch/distance/distance_limits/pan_limit`，复位恢复该模型的初值，不移动模型。
- 桥默认距离边界保持 0.38～1.65 m、俯仰 0.12～1.25 rad；平移相对初始中心的总偏移最多 0.18 m，垂直偏移最多 -0.06～0.12 m。其他模型应按自身单位和尺寸传 settings，不复制桥的数值。

桥适配位于 `drag_interaction.gd`：`input_adapter` 可替换；`handle_pointer(command)->bool` 处理公共命令并用原 `drag_contract` 发装配请求，true 表示应标记该 viewport 输入已消费。`app/bridge_workshop.gd` 只注入命中/卡片/遮挡回调与相机操作。`ui.world_input_blocked(point)` 统一返回可见面板和模态遮挡，旧的左键旋转模式开关改为默认空白旋转说明；右键旋转及复位保留。

ESC、模态禁用、失焦及节点退出会清理捕获和预览；取消后的迟到松开不提交。桥装配判定、库存、槽位/撤除规则和绘画笔触不属于本包，本轮未更改。船需自行提供相同上下文及相机 settings，本轮未修改船或关卡接线。

`part_operable` 指可开始拖动预览，不等于允许装配提交。桥保留原来“依赖未满足时仍可拿起、红色预览、松手拒绝”的反馈；`eligible`、库存和兼容性继续由原拖动契约/模型规则处理，公共路由不判定装配合法性。
