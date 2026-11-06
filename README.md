# BioWorkbench · 转录组分析工作站

BioWorkbench 是面向人和小鼠 Bulk RNA-seq 的本地分析与科研绘图工作站。通过浏览器配置输入、运行 R 分析、审阅结果并导出图表。既可从 Count 和分组开始，也可直接导入已有的差异表达结果、归一化矩阵或网络节点与边。

[操作指南](操作指南.md) · [项目介绍与适用范围](介绍.md) · [版本记录](CHANGELOG.md) · [第三方组件](app/THIRD_PARTY_NOTICES.md)

## 启动

1. 下载并解压源码。安装 Windows 版 R（本版在 R 4.5.1 上验证）以及所需 R 和 Bioconductor 软件包。
2. 双击 **Start.cmd**。启动器会查找 PATH 或 Windows 注册表中的 R。也可运行下面的 PowerShell 命令显式指定 Rscript。
3. 打开启动窗口显示的本机地址，默认端口为 7878。保持启动窗口开启。

~~~powershell
.\launch.ps1 -Rscript '<R 安装目录>\bin\Rscript.exe'
~~~

已安装的依赖可在工作站系统设置中查看，也可执行 `Rscript app/tools/dependencies.R`。功能所需包按模块使用，公共参考库按工具与物种配置。

## 核心功能

- Bulk RNA-seq 分步审核，以及独立的 PCA、差异表达、火山图和热图。
- GO／KEGG 过度代表分析、GSEA、GSVA、免疫相关基因集评分，以及 PPI 数据准备和独立网络编辑器。
- 通用科学绘图、科研组图排版、任务历史和结构化输入错误提示。多数图形可从已有结果重新绘制，导出格式按工具提供。

源码包包含程序、合成示例、测试和说明。用户输入、任务记录、缓存、公共参考库副本和运行结果保存在本机。KEGG、Reactome 等公共参考的获取可能需要联网。工作站用于本地科研探索及图表制作，具体输入和解释边界见[适用范围](介绍.md)。
