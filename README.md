# 爱弥斯 Token Pet

爱弥斯是一个独立的桌面悬浮互动角色：Mac 版可显示 Codex Token / 前台软件状态，并有多素材人物预设、触发图片、点击语音和触发语音。

## 项目结构

- `outputs/CodexTokenPet`：macOS AppKit 源码与启动器。
- `outputs/AemisTokenPet-Windows`：Windows WPF/.NET 8 源码。

## 互动事件

每个人物预设可批量绑定图片与触发语音，条件包括：连续点击 2 次、5 次、15 次、15 秒未互动、切换前台软件。点击语音另行保存并随机播放。人物预设包采用跨平台 `.aemispreset`（ZIP）文件，内含 JSON、人物图和音频素材。

## 发布提醒

Windows 单文件 exe 超过 GitHub 普通仓库的 100 MB 单文件上限，应作为 GitHub Release 附件发布，而不要直接提交到仓库。
