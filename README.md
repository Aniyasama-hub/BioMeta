# biometa (Beta)

biometa 是一套在本机运行的转录组分析工作站，面向研究肿瘤、免疫及相关疾病机制的人和小鼠 Bulk RNA-seq 数据。当前版本为 **0.2.0-beta.1**，包含分析工作站和 **BioMethod (Beta)** 方法知识库。

项目把分析、绘图和结果整理放在同一个流程里。可以独立使用 PCA、差异表达、火山图、热图、GO、KEGG、GSEA、GSVA、PPI 和免疫评分，也可以按步骤完成 Bulk 分析，挑选图片后组图。通用绘图还包括矩阵图、Circos、桑基图、韦恩图等，共 21 个工具入口。

## 项目侧重

- 分析与重绘分开：修改颜色、字号和图例时，尽量复用已有计算结果。
- 每项任务保存输入、参数、版本和日志，结果可导出作图数据及独立 R 脚本；失败任务可下载诊断包。
- 自动流程支持逐步配置、返回重跑、标星选图及最终排版，不要求一次接受所有默认参数。
- BioMethod 与工作站互相跳转，提供原理、操作、逐行代码教学和参考资料。当前有 18 篇文章、9 个源码索引和 15 条参考资料。

## 下载与配置

[下载 Beta ZIP](https://github.com/Aniyasama-hub/BioWorkbench/archive/refs/heads/main.zip)，完整解压；或者克隆同一仓库：

```powershell
git clone https://github.com/Aniyasama-hub/BioWorkbench.git
cd BioWorkbench
```

安装 R 后，用自己选择的 Rscript 执行以下命令。路径只是示例，本轮测试环境为 Windows、R 4.5.1。

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' app/tools/bootstrap.R --install
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' app/tools/bootstrap.R --check
.\Start.cmd
```

首次启动需要选择 Rscript.exe；之后可在设置中嗅探并指定不同版本。包安装需要访问 CRAN/Bioconductor。ZIP 和仓库都不捆绑 R；详细步骤见 [安装说明](INSTALL.md)。

## 怎样开始分析

1. 启动后，在设置中选择示例数据熟悉操作，或直接上传自己的文件。Count 分析需要原始计数和分组；通路分析通常读取完整差异结果或排序表，GSVA 读取逐样本表达矩阵。
2. 从首页选单项工具，或进入 Bulk 流程。确认物种、比较方向、编号列、筛选条件和图形设置后运行。
3. 查看图像、映射摘要和结果表。单纯改样式可重绘；改变分析条件则重新计算。流程中的图片可标星，到排版步骤选用。
4. 下载单个文件或完整结果包。遇到错误时先看具体提示，再从任务记录导出日志排查。

左上角项目菜单可进入 BioMethod。所有知识条目仍按定义、原理、操作、适用范围和参考资料维护。

## 版本与适用范围

[更新说明](RELEASE_NOTES_v0.2.0-beta.1.md) · [复检报告](app/docs/beta-review-2026-11-09.md) · [项目结构](ARCHITECTURE.md) · [操作指南](操作指南.md) · [第三方说明](app/THIRD_PARTY_NOTICES.md)

本轮 14 个回归套件通过，覆盖示例分析、出图和主要前端交互。当前面向 Windows 本地单用户使用；未验证所有系统、R 版本或研究设计。公共注释会随数据库版本变化，编号冲突需要核实，不能通过删除报错基因代替检查。输入、设置和结果保存在本机，不随源码分发。
