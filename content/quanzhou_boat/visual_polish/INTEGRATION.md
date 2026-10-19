# 船与桥视觉接入说明

本目录只提供可选的表现资源，没有装配规则、输入、镜头或动画控制。没有修改船、桥或项目配置的现有文件。由集成负责人选择下面的最小接入点。

## 实际参考与取值

已读取并对比本副本的以下资料：

- `docs/validation/inventory_complete.png`、`redesign_complete.png`：现行浅色桥 UI、红棕木件与地面投影。
- `ui/workshop_ui.gd`：面板、字体、按钮、托盘、文字反馈的实际参数。
- `app/workshop_stage.gd`：背景、环境光、主光、补光、地面材质。
- `content/luban_bridge/materials/redwood.gdshader`、`bridge_presenter.gd`：木纹色、粗糙度、低反射、构件 variation。
- `content/quanzhou_boat/evidence/01_overview.png`：整改前深蓝背景、默认深色按钮与白字；与上述桥有明显差距。
- 当前正在变动的 `boat_play.gd`、`boat_style.gd`、`wood.gdshader`：已看到集成负责人正在加入浅色布局、红木与剖切参数，本目录不覆盖它们。

`docs/validation/05_full_model_rotated.png` 是深色旧桥界面，未用作当前样式目标。

| 项目 | 与现行桥一致的值 |
| --- | --- |
| 主底 / 面板 / 文字 / 次级文字 | `eae6df` / `fbf8f2` / `443a30` / `8e8173` |
| 边框 / 进度填充 | `ded7cb` / `a48352` |
| 悬停底与边 | `f3ede2` / `c8b795` |
| 按下底与焦点边 | `e9dfcf` / `b79865` |
| 成功 / 错误 / 目标文字 | `627455` / `9a5140` / `687e5e` |
| 字体顺序 | Microsoft YaHei UI → Microsoft YaHei → Noto Sans CJK SC |
| 标题 / 分区标题 / 正文与按钮 / 注记 / 页脚 | 30 / 21 / 15 / 13 / 12 px |
| 工具按钮 | 集成方保留 48 px 高；横向间隔 10 px；圆角 12 px |
| 说明卡 / 托盘 | 卡内边距 20 px、圆角 16 px；托盘内边距 12 px、圆角 18 px |
| 正常构件 / 未可装构件 / 选中边 | `eee4d2` / `f6f2e9` / `b69a6c` |
| 木纹暗 / 明 | `(0.25, .085, .043)` / `(.43, .185, .095)`，与桥 shader 原值一致 |

禁用按钮、下拉弹出层、滚动条与滑块沿用同一色系，补齐了当前简单 `boat_style.gd` 未覆盖的原生控件默认深色。禁用文字仍可读；状态同时用文字说明，不靠颜色表达。没有增加闪烁、发光、彩色大按钮或新的风格。

## 最小接入：仅替换一行 preload

当前 `boat_play.gd` 已有 `Style.theme()`、`Style.button()`、`Style.panel()` 与 `Style.MUTED/PAPER` 调用。本 helper 保持这些接口兼容，因此集成负责人可以只应用：

```diff
-const Style = preload("res://content/quanzhou_boat/boat_style.gd")
+const Style = preload("res://content/quanzhou_boat/visual_polish/bridge_style.gd")
```

此行不会改变装配、拖拽、近景或动画。`panel(color, padding)` 的现有调用继续有效，附加可选参数为 `radius` 与 `shadow`。

若需要进一步贴齐桥的细节，可显式改两处面板调用（可选）：

```gdscript
step_card.add_theme_stylebox_override("panel", Style.panel(Style.PAPER, 20, 16, true))
tray.add_theme_stylebox_override("panel", Style.panel(Style.PAPER, 12, 18))
```

**文字颜色注意**：已有 `.modulate = Style.MUTED` 会乘上主题的棕色，使次级文字过暗。改用 `Style.label(label, "caption", true)` 或单独 `add_theme_color_override("font_color", Style.MUTED)` 并将 `modulate` 置为白色。只对该条文字处理；不要递归覆盖全部控件样式。

## 构件与反馈接入（可选）

由现有 `_refresh()` 的状态计算处调用 `Style.card(cards[id], state)`，`state` 为 `available`、`selected`、`installed`、`locked`。helper 不设置 `disabled`、不连接信号、不改变点击或拖拽区域。继续使用现有状态文字和缩略图。若旧代码已设置整个卡片 `modulate`，集成方应选择一种降级表现，避免主题禁用颜色与父节点透明度重复相乘。

反馈文字由现有业务判断后调用：

```gdscript
Style.feedback(message, "success") # 正常契合 / 安装完成
Style.feedback(message, "error")   # 非法松手 / 前置条件未满足
Style.feedback(message)            # 普通操作说明
```

helper 不改 `message.text`。主题无法覆盖已有的显式颜色/字号覆盖；请在原反馈赋值点接入，而不是定时重刷整棵 UI。

## 木材与光照（可选参数 helper）

```gdscript
const Surface = preload("res://content/quanzhou_boat/visual_polish/bridge_surface.gd")
```

`Surface.lighting(env, light, fill, shadow_distance_m)` 复用桥的环境参数：白色环境光 0.48、Filmic / exposure 0.9；主光 `(-62,-32,0)` / 0.8 / 暖白，补光 `(-35,145,0)` / 0.28。同桥的 angular distance 1.1、shadow blur 1.5 与 bias 0.025。**船已有对应设置时无需再次调用**。桥的阴影距离是 3m；当前船集成代码使用 12m，应保留船所需覆盖距离，以免帆桅阴影被截断。显式传 `12.0` 即可，其余参数一致。

`Surface.ground_material()` 只返回与桥一致的灰色粗糙地面材质，不创建地面、不移动模型。船的地面 y 必须由实际船底包围盒决定，不能照抄桥的 0.0048m。

在 `_restore_wood()` 新建木材后可调用：

```gdscript
Surface.wood_parameters(material, key, grain_axis)
```

仅写入 shader 已声明的 `wood_dark`、`wood_light`、`grain_axis`、`variation`；**不替换 shader，不碰 `section_*`、`cutaway_enabled`、`reveal_*`、`model_scale`，不接触帆、绳、金属材质**。当前船 shader 已取桥的红棕值，保持现状也可。grain_axis 必须是该 mesh 局部坐标中的木纹长向；不要把世界坐标轴不经转换直接传给旋转过的构件。模型源单位与 shader 的 model_scale 留给集成负责人保持。粗糙度 `.67 + broad*.12` 与 specular `.27` 已在现有船 shader 中对齐桥，无需重写材质。

## 独立检查与校样

`preview.gd` 只加载本目录两个 helper，校验样式参数、禁用状态不被修改、光照参数，以及剖切/显露参数不被木材 helper 覆盖。未加载船场景或桥场景、未触发外部 API。

在本目录运行现有 Godot 4.7.2：

```powershell
& '<现有 Godot exe>' --headless --path . --script preview.gd --log-file validation.log
```

成功标识为 `VISUAL_POLISH_CHECK_OK`。`-- --render` 为可选独立引擎校样：使用现有 Godot 的独立进程，以 `--resolution 16x16 --position '-32000,-32000'` 将其窗口移到屏幕外，脚本同时设置窗口不获取焦点。控件只在 1400×900 SubViewport 内绘制，再保存 `preview.png`。脚本通过 `RenderingServer.force_draw(false)` 完成离屏窗口的绘制，避免等待 Windows 暂停的自动窗口呈现。也可用 PowerShell `Start-Process -WindowStyle Hidden` 启动这个独立进程。它不会切换或操作用户正在看的船窗口，也不读取桌面像素。`preview.png` 是 UI 资源校样，模型区明确标注占位，不宣称它是最终船场景。渲染需要图形驱动，不能与 `--headless` 同用。运行时日志只含本工具检查结果；不含凭证。

本次已用现有 Godot 4.7.2 完成 headless 检查和独立 OpenGL SubViewport 渲染；结果分别见 `validation.log` 和 `render.log`，均无报错。运行时 APPDATA 定向到 `%TEMP%/boat-polish-godot-profile`，未安装任何软件、未修改项目配置。

接入后的完整船、近景、遮挡、窄窗口布局和动画仍由集成负责人在其独立场景验收；本资源校样不能替代最终整合验收。
