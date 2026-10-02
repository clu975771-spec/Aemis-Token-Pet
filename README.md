# 爱弥斯 Token Pet · v03（2026-10-02）

macOS 原生 Swift/AppKit 桌宠，带 Codex 任务提醒与爱弥斯皮肤联动。本版仅包含爱弥斯内置角色。正式动画使用透明 PNG 分层与 JSON 参数运行器；Cubism 转换件仍是实验转换结果，未作为精修成品发布。

保留独立待机发束与后马尾、随机眨眼、连点闭眼、点击回弹、AVAudioPlayer 音频驱动口型、共用 0–200% 人声音量、任务完成/问题去重、多屏位置记忆和“让我想想”随机表情。

## 构建安装

需要 macOS、Xcode Command Line Tools（`xcode-select --install`）与 Python 3。克隆仓库后运行 `zsh outputs/CodexTokenPet/install.sh`。安装器先编译，成功后复制源码和随包资源到 `~/Library/Application Support/CodexTokenPet`，注册并重启 LaunchAgent。直接运行 `zsh outputs/CodexTokenPet/launch-token-pet.sh` 可从源码目录启动。安装会保留偏好、聊天记录和用户自定义资源。

验证：`zsh outputs/CodexTokenPet/tests/run.sh`。所有人声从预制语音银行读取，100%以上使用预先限幅档位，运行时无需 TTS。安装器从银行100%版本补齐缺失的旧路径别名；部分别名扩展名沿用旧命名，实际内容为WAV，由AVAudioPlayer按文件内容识别。

随机表情优先读取程序旁 `assets/emoticons` 中的 PNG/JPG/GIF，也兼容用户自己的 `~/Desktop/爱弥斯/图片/桌宠表情包_20260822` 与 `~/Desktop/爱弥斯/爱弥斯演唱会捏捏-gif`。项目外私人表情库未随仓库上传；未安装素材时表情菜单无图可播，其他功能正常。

## Codex 与皮肤

桌宠只在本机读取 Codex 状态和用量；没有显式目标的普通回复不会被当成整个任务完成。完成、失败与待处理提醒的准确触发语义见桌宠README。数据库格式随Codex升级可能变化。

`native-startup` 保留爱弥斯同窗启动、皮肤脚本与源码；它依赖本机Codex应用及其调试接口，属于可选组件。现有安装使用方法与还原方法见其中的使用说明。没有打包用户Codex日志、账户数据库或应用内部检查转储。

Windows旧版源码继续保留在 `outputs/AemisTokenPet-Windows`；本次v03升级只验证macOS，Windows未同步分层运行器。

## 资源声明

本项目为《鸣潮》爱弥斯的非官方同人桌宠，角色及相关原始素材权利归各权利人。随包图像与克隆语音用于本项目展示，不代表获得商用授权；无权将这些资源作为自由商用素材再分发。第三方应用和服务不随包分发。项目未为第三方角色素材授予开源许可。
