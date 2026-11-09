# biometa / BioMethod (Beta) 安装

版本：0.2.0-beta.2。面向 Windows 本机使用。ZIP 和 Git 获取同一套程序、公开示例、界面翻译与 R 安装资源。

## 下载

[下载 ZIP](https://github.com/Aniyasama-hub/BioWorkbench/archive/refs/heads/main.zip)，完整解压到可写目录；也可克隆：

```powershell
git clone https://github.com/Aniyasama-hub/BioWorkbench.git
cd BioWorkbench
```

不要在压缩包内运行。普通完整克隆即可，无须 Git LFS。

## 首次启动

双击 `Start.cmd`。脚本查找 PATH、Windows 注册表和常见安装目录：

- 发现一套可运行的 R，自动保存并使用。
- 发现多套，列出版本和位置，由你选择；也可浏览 `Rscript.exe`。
- 没有发现 R，询问是否使用附带的 R 4.6.2 安装包。“否”从国内 CRAN 镜像下载当前版本；“取消”转到浏览已有 R。关闭选择窗口可结束启动。

安装向导由用户确认和操作。附带安装包拆成分卷保存在 `installers/`，启动器自动合并并检查 SHA256，无须手工拼接。来源和校验值见 [安装资源](installers/README.md)。

缺少必需 R 包时会询问是否安装，同意后显示日志。R 安装包可离线使用，R 包和公共注释并未全部离线打包，首次准备仍需要 CRAN/Bioconductor 网络访问。系统设置可指定兼容的专用 R 包库。

## 日常启动与设置

启动器自动打开本机浏览器并隐藏到系统托盘。首次准备完成后，项目目录生成带自定义标志的 `biometa.lnk`，可直接双击。`Start.cmd` 继续保留；`.cmd` 文件自身使用 Windows 的脚本图标。

右键托盘图标可打开工作站、刷新整个工作站或退出。刷新会重启本启动器创建的 R 服务，退出会结束该服务及其后台子进程；有运行任务时先询问。

关闭浏览器不会退出服务。默认地址为 `http://127.0.0.1:7878`；占用时自动寻找后续端口。双击托盘图标可打开实际地址。重复启动同一目录不会再创建服务。

首次探测和界面设置共用 `app/results/toolbox/settings.json`。在设置中更换 R 后，通过托盘退出再启动。**设置 → 界面风格** 可保存四种界面语言；教程正文及代码注释保留原文。

## 手动检查与排错

需要查看命令行日志时，可使用保留的控制台入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\launch.ps1 -Rscript '你的R安装目录\bin\Rscript.exe'
```

在项目目录用选定的 R 检查或安装依赖：

```powershell
& '你的R安装目录\bin\Rscript.exe' --vanilla app/tools/bootstrap.R --check
& '你的R安装目录\bin\Rscript.exe' --vanilla app/tools/bootstrap.R --install
```

启动日志在本机 `logs/`，任务日志在任务记录中。失败任务可导出诊断包。发布包不含个人配置、任务结果、研究数据和开发审查文件。

本版已用现有 Windows / R 4.5.1 环境验证启动和界面。附带 R 4.6.2 安装包已核对来源与哈希，未在全新 Windows 上实际安装全部 R 包。不同 R / Bioconductor 版本的兼容性以实际安装结果为准。
