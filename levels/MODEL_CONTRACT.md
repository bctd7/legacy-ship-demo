# 通用模型、阶段与 2D 素材契约

新增实际模型只需提供模型包、模型描述和本关配置。无需修改 level_flow.gd、model_stage.gd、drawing_stage.gd、drawing/ 或 image_generation/。本关的桥、船名称只属于关卡配置、素材及独立模型适配器；通用逻辑不按模型名称判断。

## 模型包需要提供

1. 稳定的模型 `id`，例如 `luban_bridge` 或其他模型标识。它独立于关卡阶段 id，一个模型可以放入不同关卡。
2. `adapter_script`：一个实现阶段接口的 Control 脚本；或 `scene`：自身实现同一阶段接口的 PackedScene。如果原玩法场景不提供接口，编写独立薄适配器，并把原场景路径放进描述的 scene。模型规则、3D 操作和自身完成判断留在模型包/专用适配器。
3. 标准生命周期 `enter_stage(config,context)->String`、`exit_stage()`、`stage_result(stage_id,result)`。结果结构见 CONTRACT.md。模型真正完成后发送 completed，payload 可保留内容快照等模型专有数据；通用层追加稳定 model_id，不解读模型规则。
4. 独立的 `drawing_asset`，例如 `{kind:"image_2d", texture_path:"res://.../render.png", transparent_background:true, placeholder:false}`。完成事件与素材引用是独立字段：装配完成并不意味着已有图片。可由描述静态提供，也可由适配器在结果 payload.drawing_asset 提供，后者优先。

纸面使用桥、船或其他模型的**透明背景 2D 图片**。素材由模型包提供固定视角渲染结果，必要时再单独风格化；绘画组件不挂可操作 3D 模型，不承担模型渲染。当前桥使用用户选定的 `levels/assets/bridge_illustration_v2.png`，2046×769 完整透明国风插画，含两端桥台支撑；这是风格化艺术候选，非精确模型复原。Library 来源与原图哈希见同名 metadata.json，GLB 烘焙素材保留作历史调试，不再默认引用。桥占位 SVG 仅保留给通用契约 fixture；可选船仍明确为占位。

`drawing_asset` 可带 `preview_texture_path`、`placed_texture_path`；配置素材也可提供同名字段。本轮默认复用同一张图。现有绘画公开 API 只接受一张 Texture2D，所以不同预览/最终图片暂不切换，适配器会清晰拒绝不同路径；`placement_transition:{kind:"reserved",duration_seconds:0.0}` 预留松手落位过渡，当前没有播放动画。后续在模型/适配边界扩展即可，不能通过引入实时 3D 绕开 2D 契约。

## 关卡需要提供

阶段列表里的模型阶段使用 `component:"model"` 与内联 `model` 描述。通用宿主只注册 model 与 drawing 两种工厂；新增模型不需要增加按模型名匹配的工厂或分支。示例：

```gdscript
{"id":"assembly", "component":"model", "model":{
  "id":"some_model", "adapter_script":"res://models/some_model/stage_adapter.gd",
  "scene":"res://models/some_model/play.tscn",
  "drawing_asset":{"kind":"image_2d", "texture_path":"res://models/some_model/paper.png",
    "transparent_background":true}
}}
```

绘画阶段的每个 material 配置稳定素材 id、result_stage（引用哪个完成结果）或直接 texture_path、归一化 target_position（中心）、display_size（最大包围框）、allowed_drop_rect（允许拖动中心的区域）、lock_on_place、layer。layer 小的在底层，大的在上层；适配器排序后传入的 materials 数组就是底到顶的绘制顺序。笔画独立位于图片上方。

构图参数保存在 level_catalog.gd：模型图片中心 (0.65,0.26)、最大尺寸 (0.40,0.30)、layer 10；原近景附加图片中心 (0.28,0.74)、最大尺寸 (0.46,0.39)、layer 20。附加图片标记 optional，当前联通入口默认排除，故不要求船图片或船拼装。level_options.include_optional_materials=true 可启用附加构图；近景图片仍与禁用的额外模型拼装阶段分开。

逻辑画纸仍为 960×640。绘画阶段可选配置 `export_size`，默认不改变组件行为；当前入口配置为 1920×1280，调用原 document.export_png 的等比例全纸导出能力，素材与笔画一起合成。结果 `paper_size` 保留逻辑尺寸，`export_size` 记录实际 PNG 尺寸。默认缩放、alpha 合成和画笔规则不变。

## 可替换性证据

tests/levels/fake_model.gd 及 fake_model.tscn 是极简契约 fixture，没有开发新实际模型。入口测试通过一个无桥/船名称的 fixture_alpha 描述进入同一 model_stage，经完成事件把图片交给同一 drawing_stage；另验 scene-only 描述。通用控制器和绘画代码无需增加模型条件分支。


## 本轮双模型接入更新

当前 `integrated_demo.tscn` 通过 `model_registry.gd` 配置桥→船→绘画；旧桥单模型验收使用 `--bridge-only` / `bridge_only` 配置。认可船图及最终船包dc59e9d已接入，实际完整流程与可见检查已完成，原生鼠标与保留项见最终交接。注册接口、完整入口、测试边界与交付依赖见 [BOAT_INTEGRATION_HANDOFF.md](BOAT_INTEGRATION_HANDOFF.md)。本节更新优先于上文旧的默认单模型/船占位说明。
