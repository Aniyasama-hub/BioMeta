# BioWorkbench · 转录组分析工作站

BioWorkbench 是面向**人和小鼠 Bulk RNA-seq** 的本地分析与科研绘图工作站。研究者可以从基因计数和样本分组开始分析，也可以直接复用已有的差异表达结果、逐样本表达矩阵或网络表。通过浏览器完成参数配置、结果审阅和图表导出，由本机 R 执行计算。

## 特点与使用场景

| 使用场景 | BioWorkbench 提供的功能 |
| --- | --- |
| 从 Count 开始分析 | Bulk RNA-seq 流程串联 PCA、DESeq2 差异分析、火山图、热图及下游分析。各步可单独检查和调整，再确认进入下一步。 |
| 已有分析结果，继续做下游 | GO／KEGG 可读差异结果，GSEA 可读带方向的基因排序，GSVA 可读逐样本表达矩阵和分组。按需选用公共参考库或自建基因集。 |
| 整理通路或网络结果 | PPI 可直接导入 Node／Edge，也可用 Count 加分组或 DEG 配合互作参考生成网络数据。独立编辑器支持节点样式、布局和网络筛选。 |
| 准备论文图表 | 可从已有分析结果调整配色、字号、图例及导出格式。组图支持逐图大小、纸张方向、实时分栏预览和在线微调。 |

本地运行会保留任务记录、输入快照、分析参数和绘图数据，便于复核与重绘。常见输入错误会指出文件名和具体问题。免疫模块提供基因集相对富集评分，适合比较表达特征。更多输入规格与解释边界见[项目介绍与适用范围](介绍.md)。

## 下载 ZIP 与启动

**[下载最新版 ZIP](https://github.com/Aniyasama-hub/BioWorkbench/archive/refs/heads/main.zip)** · [下载 v0.2.0 固定快照](https://github.com/Aniyasama-hub/BioWorkbench/archive/da098b28a121cc6c9b2f9b64c3e411c15e8d0a24.zip)

1. 点击上方链接，或在仓库主页选择 **Code → Download ZIP**，将压缩包完整解压到本机。
2. 安装 Windows 版 R 与所需的 R／Bioconductor 包。本版在 R 4.5.1 上验证，依赖清单见 [依赖检查脚本](app/tools/dependencies.R)。
3. 在解压目录双击 **Start.cmd**。浏览器打开本机页面，默认端口为 7878，以启动窗口显示的地址为准。
4. 如果电脑有多套 R，可在 PowerShell 中显式指定装好依赖的版本。

~~~powershell
.\launch.ps1 -Rscript '<R 安装目录>\bin\Rscript.exe'
~~~

可用 `Rscript app/tools/dependencies.R` 检查当前环境已安装的包。ZIP 提供工作站源码、合成示例与文档。R 和依赖需本机安装，部分公共参考库的首次获取需要联网。

[操作指南](操作指南.md) · [项目介绍与适用范围](介绍.md) · [版本记录](CHANGELOG.md) · [第三方组件](app/THIRD_PARTY_NOTICES.md)
