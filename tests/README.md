# 当前有限测试入口

用已有 Godot 控制台程序依次运行六套检查：

```powershell
.\tests\run_checks.ps1 -GodotConsole '已有的 Godot 控制台程序完整路径'
```

任一失败即停止。日志和截图写入 `docs/validation`。当前实际项目结果为370项通过；它们使用 Godot 输入事件注入，不是实体鼠标或触摸屏验收。

| 当前脚本 | 项数 | 检查范围 |
| --- | ---: | --- |
| `verify_drag_identity.gd` | 34 | 来源锁定、扫过错误/占用槽与托盘、连续下一件、取消观察重置 |
| `verify_pose_preview.gd` | 32 | 单一跟手预览、几何中心支点、反向朝向、候选滞回、按住不跳高；合法松手才执行原完整高入口动画 |
| `verify_inventory_slots.gd` | 116 | 两种完整顺序、库存/槽位/快照、按钮与拖动撤除、取消及最终22网格 |
| `verify_surface_targets.gd` | 89 | 五根圆柱各两端、同槽重复拒绝、五处桥面中心、共同板面跟手与目标朝向、内部错误规格/依赖拒绝 |
| `verify_centre_beams.gd` | 52 | 实际全三角面等价、共享中梁前后/边缘互换、邻槽和占用拒绝、旧快照迁移、取消重置 |
| `verify_deck_family.gd` | 47 | 单卡桥面×5、五目标、三种实际规格、17/20剩余3件、取消/占用/重复拒绝、按住不跳高、旧快照及完整撤除 |

日志：[来源锁定](../docs/validation/verify_drag_identity.log)、[单件跟手](../docs/validation/verify_pose_preview.log)、[完整装配撤除](../docs/validation/verify_inventory_slots.log)、[桥面与双端](../docs/validation/verify_surface_targets.log)、[中梁](../docs/validation/verify_centre_beams.log)、[桥面合并](../docs/validation/verify_deck_family.log)。[手动验收](../docs/操作与验收.md) 与 [当前架构](../docs/架构说明.md) 另列。

`verify_gui.gd` 及其他旧入口保留为当前库存回归的兼容包装器；其原内容完整保存在 `archive_before_inventory/`，目录通过 `.gdignore` 排除自动扫描。归档脚本针对旧字段，不列为当前通过项；旧日志只对应原版本。

桥仍待用户最终验收；这些检查未覆盖真实触摸、多点输入、LAN、船内容、重力自承或承载能力。

本地Git不跟踪 `.log` 临时结果，运行入口可重建；[当前检查摘要](../docs/validation/current_checks.json)保留验证范围与结果。
