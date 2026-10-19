# 当前文档目录

当前状态以根目录 [README](../README.md)、[操作与验收](操作与验收.md)、[架构说明](架构说明.md) 和 [测试入口](../tests/README.md) 为准。桥仍待用户最终验收，船与 LAN 未接入，GitHub 未操作。

## 当前版本

- [操作与验收](操作与验收.md)：单件跟手、目标朝向、松手后原动画、库存、撤除、手动清单与验证限制。
- [架构说明](架构说明.md)：现有分层、数据契约、快照与几何证据。
- [测试入口](../tests/README.md)：六套有限检查及日志。
- [中梁互换截图](validation/centre_beam_interchange.png)
- [桥面互换截图](validation/deck_surface_interchange.png)
- [统一桥面卡17/20截图](validation/deck_family_17_of_20.png)
- [单件预览截图](validation/single_pointer_preview.png)

## 船研究资料

- [项目方案讨论稿](船研究/项目方案讨论稿.md)：原 README 的船讨论内容，保留历史状态标记。
- [素材调研](素材调研.md)：原船素材资料保持原文件；下载、授权及当前船资产进展需在独立船任务中核实。

研究资料不是已接入内容或已验收资产，桥验收通过前不据此推进船接入。

## 历史与恢复

- [整理前全部原文档](archive/bridge_docs_before_ship_20261016_005110.zip)：ZIP 内保留原相对路径和 SHA-256 清单，归档逐文件核对后才移除过时活动说明。
- `backups/`：代码调整前备份与重构前功能快照，继续保留。
- `validation/`：当前与历史日志、截图及核对报告。旧日志只对应当时版本，不能替代当前通过项。
- `../tests/archive_before_inventory/`：旧测试原内容，当前兼容入口不执行这些旧字段逻辑。

本机 `backups/` 和 `archive/` 的历史ZIP及临时日志被 `.gitignore` 排除；源码提交保留当前文档、必要资源、验证证据JSON与截图。测试日志运行当前入口后重建；[当前检查摘要](validation/current_checks.json)保留在版本中。
