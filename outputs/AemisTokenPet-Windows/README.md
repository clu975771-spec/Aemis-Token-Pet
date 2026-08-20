# 爱弥斯 Token Pet · Windows 预览版

这是原生 WPF（.NET 8）工程，不依赖 Electron。支持置顶透明悬浮窗、右键角色工作台、人物替换、颜色、气泡/人物大小、透明度、连点速度和连点台词。

## 在 Windows 构建

1. 安装 [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)。
2. 将整个仓库下载到本机，PowerShell 中进入本目录。
3. 执行：`dotnet run`

发布为单文件 exe：

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

说明：Windows 的 Codex Token 本地数据库路径尚未经过真机确认，所以本预览版将 Token 区留作状态文字；爱弥斯的交互功能可直接运行。

## 跨平台人物预设包

右键人物可导入或导出 `.aemispreset` 单文件。它是 ZIP 格式，包含人物 PNG 与 `preset.json`，可在 Mac 和 Windows 两版之间互相导入，适合直接发送给朋友。
