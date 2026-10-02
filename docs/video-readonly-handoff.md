# 介绍视频只读接口

正式运行器：pet/AemisLayeredRig.swift；主程序：pet/CodexTokenPet.swift。PNG与JSON：pet/assets/aemis-rig-v03（rig.json及textures）。请用这些正式资源，不依赖旧backup或其他角色。

同款音频：pet/voice-assets/unified/manifest.json 中每个clip的file映射到统一银行；normalized/*/100.wav为标准音量。点击克隆短句：pet/voice-assets/click-clone；完成与问题：pet/voice-assets/task-alerts。原生播放链路：pet/UnifiedSpeech.swift，AVAudioPlayer音量与口型联动见主程序。无需读取用户凭据或生成新语音；本地TTS服务并非成品运行依赖。

使用：安装后右键桌宠，可调声音0–200%、任务提醒、多屏位置记忆、随机表情频率。随机表情标题为“让我想想”，12秒消失，任务提醒优先。v03为原生PNG+JSON，不称为精修Cubism模型。

视频输出promo-video由视频窗口管理，不属于源码发布范围。不要改Swift、安装器或运行中设置。
