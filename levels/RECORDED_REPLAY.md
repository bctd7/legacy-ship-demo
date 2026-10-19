# 已生成图片离线回放

本入口复用 `GenerationStage` 的 `Job.finished → _received → 保存 PNG / ImageTexture 显示 / 阶段结果` 路径，但不创建 `Service`、provider 或 HTTP transport。不读取密钥、不访问 8769，不发送真实 API 请求。主入口 `project.godot` 保持不动。

默认回放素材是另一线程此前独立真实 API 调用成功得到的 `tests/image_generation/fourth_real_bridge/seedream_pro_bridge_result.png`，2368 × 1776。其真实 API 成功证据由生图线程维护。本次验收仅证明该已有结果可以进入关卡回调与 UI，不是本轮点击到真实 API 的端到端验收；右图也不是根据本次左侧绘画重新生成。

## 最短试玩

1. 在项目目录执行 `powershell -File .\levels\run_replay.ps1`。
2. 完成桥拼装，进入白纸绘画；拖入模型图片、画几笔，然后点击“导出绘画并完成本阶段”。
3. 点击“已生成图片离线回放”，再点击“显示已生成图片（离线）”。图片按原始 4:3 比例居中显示。
4. 点击“返回绘画”；原笔迹、素材和进度保留。导出后画纸仍维持既有锁定语义。

回放入口只在显式传入 `--replay-image=<已有图片路径>` 且绘画已完成后出现。打开面板不会自动读取结果，重复点击不会增加读取任务。缺图/解码失败可手动重试，关闭或取消后迟到结果不写入。

## 验收

`tests/levels/verify_replay_level.tscn`：桥完成用有效快照测试夹具；绘画使用真实鼠标事件拖入素材、画笔并导出。检查缺图恢复、取消、重复点击、幂等回调、原像素保存、2368 × 1776 纹理及 4:3 等比显示、返回保留同一文档/笔迹/素材/导出像素、关闭时抑制迟到写入。

证据：`tests/levels/replay_evidence/validation.json` 与 `replay_success.png`、`replay_failed.png`、`replay_return_drawing.png`。测试不启动任何本机服务。
