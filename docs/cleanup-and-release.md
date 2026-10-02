# 2026-10-02 清理与发布记录

正式仓库： https://github.com/clu975771-spec/Aemis-Token-Pet 。确认另一个近似名称仓库为空，未创建新仓库。

删除前完整项目备份： ${HOME}/Documents/ChatGPT-project-backups/aemis-before-cleanup-20261002 。仅从本项目删除其他角色；桌面爱弥斯文件夹未改动。删除pet/backups、pet-live2d/backup中的旧版本，删除角色图片，移除其他角色人设分支、菜单入口和测试组合；文件清单见cleanup-removed.json。旧内置角色ID启动统一回爱弥斯。

发布仅包含审核后的macOS正式源码、PNG+JSON、语音、皮肤源码/资源、文档与已有Windows旧版；未上传本地备份、虚拟环境、node_modules、视频制作输出、Codex账户数据/日志或检查转储。项目内未发布的爱弥斯制作资料仍保留。项目外原始素材和本地服务配置不发布。

验证：Swift优化构建通过（CIWarpKernel仅有macOS弃用警告）；任务提醒/去重、显示器重连与坐标变化、100–200%限幅测试通过；20条源路径的0/50/100/160/200%统一银行路由通过。正式LaunchAgent已注册并运行。已有动画r4离屏验收记录保留，未把以前的动画验收冒充本次完整桌面交互复测。

随机表情兼容原用户路径并支持随程序assets/emoticons目录；本机保留原表情库，发布不包含用户项目外私人素材。README如实标注Cubism转换未精修、Windows未升级以及Codex数据库兼容性限制。
