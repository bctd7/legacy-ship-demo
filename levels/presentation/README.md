# 关卡表现层与运行范围

本层只负责外观与宿主布局。level_theme.gd 沿用桥面板的象牙白、木棕、中文系统字体和按钮间距；drawing_panel.gd 组织面板和说明。原 drawing_surface 的 _draw 读取可选 DrawingSurface 主题令牌，没有主题时保留默认表现。白纸保持纯白，素材、笔画、导出和所有输入方法不变。不复制绘画组件、不跨包读取其私有手势字段，不包含模型名称分支或模型规则，不修改模型几何，也不提供船玩法。

drawing/drawing_toolbar.gd 是独立演示与关卡共用的小型 Control，仅绑定既有公开操作、刷新撤销状态、发出清空确认请求。清空确认、导出和阶段完成仍由各自宿主负责；drawing/ 不依赖 levels/。纹理路径在适配器解析：res:// 使用导入的 Texture2D/Image 资源，user:// 和文件系统 PNG 按文件读取。

## 有引用证据的清理

- 原 drawing_stage._build_tools/_button 仅在该文件内部被调用；独立 drawing_demo._refresh_tools 也没有外部调用。两处重复工具绑定收敛到 drawing_toolbar，保留 drawing_demo.undo_button/redo_button、_request_clear 和 clear_dialog 供既有入口与测试使用。
- bridge_presenter.completed 只有声明和一次赋值，没有读取；workshop_ui.current_index 同样只有声明和 set_state 赋值，删除这两项。preview_target_slot、app.tray 被现有交互测试读取，保留。
- 桥反馈颜色与去重进入 workshop_ui.set_feedback，去重键包含文字和错误状态；协调根只保留日志调用。同文从提示切到错误会刷新颜色。
- level_demo.tscn、first_level、pending_stage、mock_stage、generation_handoff 均有诊断/契约测试引用，保留。没有删除未来模型接口、用户文件或凭名字判定废弃的场景。

引用核查使用 rg 在 app、ui、content、drawing、levels、tests 全部 GDScript 中检索实际符号及调用。drawing/CONTRACT.md 中旧的未落盘关卡文件与必经额外模型计划已改为实际入口和模型契约链接。

## 8 GB / 1080p 目标的有限运行检查

目标资料为 Win10、十代 i5（具体型号未知）、8 GB RAM、128 GB 存储、1920×1080 红外触摸一体机；显卡未知。本轮实际渲染机器是 RTX 4070 Laptop GPU，未在目标机测帧率或长时运行，不能据此承诺目标性能。

- 保持现有 Compatibility，无新增灯光、后处理、实时模型渲染、美术纹理或系统依赖。操作目标框和兼容槽位是必要引导；引擎碰撞/导航调试绘制默认关闭。
- 当前模型阶段保留实时镜头/装配渲染。退出桥时先禁用整棵玩法树的 process、停止子视口更新并断开适配订阅，之后由流程移除并释放场景。绘画阶段实测没有残留 SubViewport；退出模型 session 的 UI/适配信号订阅归零。
- 绘画没有 _process 循环，笔画按输入更新；配置、文档变化和布局变化才请求视图刷新。空闲帧不重建文档纹理，纸面重绘不改变导出像素。样式资源只在宿主主题创建时分配并复用。
- 重置后 surface 与 document 的弱引用失效，源图片/笔画不通过本层全局缓存保留。当前默认一张模型图片，附加构图图片为可选配置；纸面为 960×640，单张 RGBA 纸面约 2.34 MiB，不含历史、临时合成图、字体及 GPU 资源。
- **仍有缺口**：通用绘画的撤销/重做命令及单笔点数尚无硬上限，源图片尺寸/素材数量也由配置约束。本轮不截断已验收撤销语义；长时展厅运行前应另定历史预算与素材准入上限。user:// 导出目录保留用户绘画，没有擅自自动删除，留存策略也待展机部署确定。

前后截图、1080p/小窗口布局与运行日志在 tests/levels/visual_evidence/。仅清理测试自身运行，未关闭系统服务或其他应用，未读凭证或触发真实图像服务。

本轮共享项目实测：视觉/布局/生命周期 41/41，原绘画回归 41/41，关卡契约 41/41，独立绘画普通入口 10/10。1920×1080 窗口保留既有项目画面比例策略，内容视口截图为 1680×1080；未改 project.godot 的缩放设置。优化前截图是此前双素材配置，优化后按最新要求为单模型素材，两者均明确使用占位图。
