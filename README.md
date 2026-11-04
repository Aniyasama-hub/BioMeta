# BioWorkbench 独立工作台

[操作指南](操作指南.md) · [项目介绍](介绍.md)

双击本文件夹的 **Start.cmd** 或 **启动工作台** 快捷方式。

浏览器将打开本机界面，默认地址为 `http://127.0.0.1:7878`。端口被占用时会自动选择后续空闲端口，以启动窗口显示的地址为准。保持启动窗口打开；按 Ctrl+C 停止服务。

本程序、计算脚本、输入副本与输出均放在此独立文件夹内，不再读取或写入“冯怡pro”项目。R 运行环境使用本机已安装且依赖完整的 `D:\R\R-4.5.1`；运行还需要相应的 R 包；换电脑后需准备 R 环境、依赖与输入文件。

```text
BioWorkbench/
  Start.cmd             双击入口
  launch.ps1            兼容 Windows PowerShell 5.1 的启动器
  app/                  前端、R 后端、配置和绘图示例
  legacy/               本程序独立使用的热图脚本副本
  data/                 当前项目输入数据的副本
  logs/                 启动日志
```

进入界面不会自动分析。默认 Count、分组、差异表和手工注释均使用 data 内的副本。新的分析结果保存在 `app/results/toolbox`，不会影响原项目。

启动失败会保留错误窗口，并将详情写入 `logs/startup-时间.log`。PowerShell 启动方式：

```powershell
.\launch.ps1
.\launch.ps1 -Port 7890
.\launch.ps1 -Rscript 'D:\R\R-4.5.1\bin\Rscript.exe'
```

功能和输入格式详见 [操作说明](app/docs/toolbox.md)。Git 仅保存程序与示例，不提交 data 中的科研输入、运行日志或结果。

本版使用图型专属样式与悬浮说明，PPI 支持 Node / Edge 双上传和离线交互图。[改版检查记录](app/docs/validation-2026-11-05.md)列出已完成验证及未重跑的真实分析范围；[第三方说明](app/THIRD_PARTY_NOTICES.md)记录 MIT 代码与许可证。

首版基线 v0.1.0：[版本记录](CHANGELOG.md) · [发布前检查](app/docs/release-review.md)。发布前新增 15 条合成后台任务检查，覆盖 14 个工具与 PPI 两种模式。
