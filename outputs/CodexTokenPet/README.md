# Codex 桌宠任务提醒

这里保存运行中 `~/Library/Application Support/CodexTokenPet` 桌宠的 Swift 源码，以及本次任务提醒所需的预制 WAV。部署脚本同步 Swift 源码、爱弥斯图片、分层资源和随包语音，会保留运行目录里已有的人物素材、聊天记录、点击语音和启动动画联动。

运行 `./pet/deploy.sh` 会编译并重启现有 `com.qianlve.codex-token-pet` LaunchAgent。`voice-assets/generate_task_alerts.swift` 只用于构建时从本机 Pinokio Qwen3-TTS 克隆音色生成 `task-alerts/raw/` 中的 WAV；随后运行 `python3 pet/voice-assets/normalize_task_alerts.py`，生成剪短开头静音、峰值约 −0.8 dBFS、整段 RMS 约 −12 dBFS 的成品。`python3 pet/voice-assets/generate_boosted_task_alerts.py` 从成品生成 105–200% 的限幅档位。默认提醒音量为 100%，菜单和设置窗口均可调到 200%；完成与问题播报共用该设置。超过 100% 时播放预处理 WAV，`AVAudioPlayer.volume` 保持在 1 以内。

## 触发语义

- “你的任务完成啦”：仅在 Codex `update_goal` 的本地运行记录明确返回 `status=complete` 时触发。Codex 会从 `goals_1.sqlite` 移除已完成的目标，因此桌宠会从对应任务的近期 rollout 记录读取这条完成事件。`thread_turns.completed` 仅表示一轮回复结束，不会触发完成播报。没有显式目标的任务无法自动认定整个目标已经完成。
- “你的任务遇到问题啦”：显式目标变为 `blocked`、`usage_limited` 或 `budget_limited`；最新一轮运行状态为 `failed`；或者任务最后一条 `final_answer` 明确带有 `questions` 字段，且之后没有用户消息。后续回复或新一轮运行会清除相应的待处理条件。
- 本机数据库没有完整公开的“等待批准”稳定字段。当前只能在批准请求以明确问题或目标受阻形式写入记录时提醒；单纯挂起的批准弹窗可能无法识别。提醒文字会准确显示“目标完成”或“需要处理”，避免将普通回合说成任务完成。
- 只提醒桌宠启动前 5 分钟内或运行后新发生的状态，防止启动时历史任务集中播报。问题可按设置的间隔重复提醒；设为 0 则不重复。已处理事件按键去重。

右键桌宠打开“声音”菜单，可直接调整持久保存的任务播报音量并试听两种播报；完整设置页“任务提醒”还可控制完成与问题开关、静音时段和重复间隔。试听使用同一播放链路和当前音量，也可在静音时段使用。自动提醒沿用原来的紧凑气泡尺寸，完成和问题分别固定显示、播报“你的任务完成啦”和“你的任务遇到问题啦”，点击气泡打开对应 `codex://threads/<任务 ID>` 查看完整任务。桌宠会跳一次，低音量播放一次现有点击声，然后播预制语音；同一任务同类提醒在 60 秒内去重。静音时段仍显示气泡与跳跃，但不发声。

本机验证运行中桌宠的声音可执行 `swift pet/tests/preview_live_alert.swift complete` 或 `swift pet/tests/preview_live_alert.swift problem`；它只播放预制声音，不弹出测试气泡。中文/英文长任务名的显示兼容性使用 `pet/tests/RenderTaskAlerts.swift` 在隔离进程离屏检查，不向运行中的桌宠发送测试文案。

位置记忆保存显示器的持久 UUID、`NSScreenNumber` 及桌宠在该屏幕可见区域内的相对位置。目标屏幕暂时缺席时，桌宠会临时回退到当前可见屏幕，且不会改写保存的目标；屏幕重现后自动归位。旧版仅保存数字 ID 的锚点会在对应显示器可见时自动补上 UUID。`pet/tests/run.sh` 使用模拟屏幕检查迟到、断连重连、ID 变化、坐标和分辨率变化以及桌宠尺寸变化，不操作真实显示器。

右键桌宠选择“将当前位置设为记忆点”会同时开启位置记忆并保存当前显示器和位置；“位置记忆：已开启/已关闭”可控制拖动后的自动归位。修复用户已有安装时应检查 `defaults read CodexTokenPet`，因为独立 Swift 可执行文件实际使用 `CodexTokenPet` 偏好域，且旧安装可能显式保存了关闭状态。

离屏检查覆盖爱弥斯及完成/问题两类状态；`pet/tests/check_rendered_alerts.py` 会验证中文、英文任务标题得到完全相同的固定中文气泡，画面始终为紧凑尺寸。
