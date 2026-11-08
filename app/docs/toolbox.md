# 本地生信工具箱：R 后端与 Shiny 前端

本版参照已完成的 TBtools-II 2.486 逆向记录，重建“分类工具、参数输入、独立计算、结果预览、多格式导出”的工作方式。它覆盖本项目的 RNA-seq 与科研绘图流程，并增加通用矩阵 PCA、热图和 Circos；没有实现 TBtools 全部数百种工具、登录授权、插件商店、序列分析或任意图元拖拽编辑。

## 启动

在项目目录双击独立文件夹中的 `Start.cmd`，浏览器会打开 `http://127.0.0.1:7878`。默认使用已经安装生信依赖的 `D:\R\R-4.5.1\bin\Rscript.exe`。

也可从 PowerShell 启动：

```powershell
.\launch.ps1
# 若该端口已被其他程序使用：
.\launch.ps1 -Port 7879
# 指定另一套已经安装依赖的 R：
.\launch.ps1 -Rscript 'D:\R\R-4.5.1\bin\Rscript.exe'
```

启动器只打开本机界面。只有点击“运行当前工具”才执行科学计算。关闭浏览器后任务可继续，前提是保持启动器中的 R 服务运行；关闭服务会清理其后台子进程。重新打开浏览器可在同一服务的历史记录中查看或取消任务。

界面只绑定 127.0.0.1；本版没有远程多用户部署设计。

## 使用顺序

1. 从首页或左侧分类选择工具。
2. 填写本机路径，或上传 CSV/TSV、Excel、GMT。每次分析由操作者选择输入。
3. 读取当前分组，确认对照组与实验组。正 log2FC 表示实验组相对于对照组上调。
4. 设置计算参数和样式，必要时点击输入检查；该检查不拟合模型。
5. 点击运行，在结果区查看实际状态、错误和日志。结果成功后才开放图像和数据下载。
6. 在图像列表中切换主图、负荷图或三维图；在数据表与文件列表中查看 CSV、RDS、参数及环境记录。

## 14 个工具入口

| 类别 | 工具 | 实现 |
|---|---|---|
| 表达与差异 | RNA-seq PCA | DESeq2/VST、高变基因、二维 PCA；同一结果派生负荷图与 PC3 可用时的静态三维图 |
| 表达与差异 | 差异表达 | DESeq2，支持有效的批次与分类协变量设计；完整表与差异筛选分开保存 |
| 表达与差异 | 火山图 | 兼容现有 log2FC 或 log2FoldChange 差异表，也可使用 Count 模型 |
| 热图与注释 | 差异/高变基因热图 | 模型 VST、筛选、行 Z-score、聚类及样式分层 |
| 热图与注释 | 自定义基因 Count 热图 | 从 04.4 脚本提取配置接口；保留基因匹配、重复名处理与布局 |
| 热图与注释 | 手工通路热图 | 从 04.3 脚本提取配置接口，保留 Excel 注释、一基因多通路和方向排序 |
| 通路与网络 | GO | 本地 org.Hs.eg.db 或 org.Mm.eg.db 配合 GO.db，或用户提供的 GO GMT |
| 通路与网络 | KEGG | 物种对应的 KEGG PATHWAY 或自建 GMT |
| 通路与网络 | GSEA | 完整有效 Wald stat 排序，整份 GMT 范围检验 |
| 通路与网络 | GSVA | VST 上计算通路评分，再使用相同设计的 limma 模型比较 |
| 通路与网络 | PPI | Node + Edge 双文件、STRING ID/分数识别、静态图、离线交互图与邻接矩阵；另可从 Count 模型筛 DEG |
| 通用绘图 | 矩阵 PCA | 已处理数值矩阵；可选 log2 和标准化，不拟合差异模型 |
| 通用绘图 | 矩阵热图 | 已处理数值矩阵、行标准化、距离、聚类和多格式输出 |
| 通用绘图 | Circos | 染色体、基因区域和连线的 circlize 绘图 |

## 数据契约

### Count 与分组

Count 使用 `gene_id`、可选 `gene_name` 和样本列。DESeq2 入口只接收非负有限整数，不把 TPM/FPKM 作为原始 Count。

分组可以是项目现有的 `Sample,Group`，也可以是 `sample_id,source_sample_id,condition,batch,include`。`source_sample_id` 精确对应 Count 列；内部 `sample_id` 单独转换为安全名称，原始 `Treatment` 组名和样本列保留不变。转换后重名会报错。`include=FALSE` 统一排除。

建模默认纳入当前选定的两个比较组，每组至少两个重复，3–30 个样本，并要求设计有残差自由度。批次缺失时的 single_batch 只是单批次占位；不会据此自动启用批次校正。

### 差异表与目标基因

火山图读取 `gene_id`、可选 `gene_name`、`log2FC` 或 `log2FoldChange`、`padj`。NA 保留为未入图/未显著数据；重复 gene_id、Inf 或非法概率直接报错。

自定义基因默认使用 `config/target_genes.csv` 的 `GeneKey,Pathway,Use`。兼容上传含 `gene_name` 或 `GeneSymbol` 的表，但不会仅凭列名宣称 GeneSymbol 一定是符号。Count 热图沿用原脚本的忽略大小写匹配与 max_mean 重复名处理。

手工注释使用 `pathway_annotation.xlsx`，保留原脚本要求的 GeneAnnotation/TargetPathways 表结构。不会从基因名猜测通路。

### 通用矩阵

CSV/TSV 第一列是唯一行 ID，其余列全部为有限数值，列名作为样本名；不要混入 gene_name 注释列。可使用 `examples/matrix.csv` 由用户手工试用。

通用矩阵默认不使用项目分组，只有明确勾选“使用分组表”才匹配上传的分组文件。热图按照所设 Top N 选取方差最大的行；若想保留全部行，将 Top N 设为至少输入行数。恒定行会在需要缩放或相关距离的准备阶段去除。

### GO / KEGG / GSEA / GSVA

GMT 每行包含 `term_id<TAB>description<TAB>gene1<TAB>gene2...`，支持 SYMBOL 或项目 gene_id。上传自建库时填写实际来源与版本。公共库由工具和物种决定，KEGG 和 Reactome 首次运行下载后按物种缓存。GO 使用本机注释包。任务保存实际参考地址、注释来源和基因集校验值。

ORA 的背景来自实际有效受检且能映射的基因。GSEA 使用完整有效 stat，不先筛 DEG；本版在整个 GMT 范围检验和校正，**不同于旧 07 脚本默认只检验指定通路的 selected_only 模式**。两者 FDR 不能直接比较。

无满足阈值的条目时保留结果表和说明，界面不伪造富集图。

### PPI

默认使用 **Node + Edge 文件模式**，两张表分别上传，无需 Count 或分组，不重新拟合差异模型。

Node 表需有唯一的 `id`、`STRING_id` 或 `gene_id`；可附 `label/gene_name`、`log2FC/log2FoldChange` 和 `group`。同时有蛋白 ID 与基因 ID 时，按 Edge 端点的覆盖关系选择；原 gene_id 保留为 input_gene_id。Edge 支持 `from,to` 或 `source,target`，可附 `score/weight/combined_score`；无分数时视为 1。`combined_score` 自动按 STRING 0–1000 转为 0–1，其他分数字段默认 0–1；可手工覆盖分数单位。

未知端点、重复节点及非法分数直接报错；孤立节点保留，同一无向边按最高分去重，自环和低分边记录到 excluded_edges.csv。不会下载 STRING 全网。交互图基于附带 MIT 许可证的 Cytoscape.js，离线可用，支持拖动、缩放、布局和 PNG 导出；下载结果包可保留完整 HTML、JS 和许可证。

另有 Count 模型筛 DEG 模式，使用基因 ID 边表；该模式不需要 Node 表。

节点数不超过 2,000 时输出加权及二值稠密 CSV；更大网络输出稀疏矩阵 RDS、边表和说明，避免 N² 内存膨胀。上限可在 `tb_network_matrices()` 的 dense_node_limit 参数中调整。Count 模式另存节点 Count；文件模式不生成不存在的 Count。

### Circos

全部为带表头的 CSV/TSV：

- 染色体：`chr,length`。
- 可选基因区域：`chr,start,end,label`。
- 可选连线：`chr1,start1,end1,chr2,start2,end2`。

使用 **0 起点、半开区间**，满足 `0 <= start < end <= length`。GFF/GTF 等 1 起点闭区间资料需先明确转换，不能直接混用。示例位于 `examples/circos_*.csv`。

## 计算设置和已确认的样式

界面采用纸色、墨绿、朱红与衬线标题。说明移到对应标题、文件输入或局部板块的悬浮提示，移开光标收起；键盘聚焦也可查看，Escape 关闭。必要单位、状态和错误直接显示。

图像默认画布 10×8 英寸、300 dpi。样式按图型提供：散点形状/透明度/坐标版式、热图色阶/名字号/边线/栅格化、富集气泡或条形、GSEA 曲线及刻线、网络节点/边/标签、Circos 轨道/角度/连线。条形图隐藏气泡大小；纯差异统计表不显示图形样式。原手工热图的基因分块、注释和方向排序仍由原布局实现；不会承诺统一默认尺寸与旧 12×15 英寸、600 dpi 输出像素相同。

模型默认低表达标准为至少 3 个样本 Count>=10；独立过滤目标 alpha=0.05，图形筛选 FDR<0.05 且 |log2FC|>=1。它与根目录旧 PCA 的总 Count 和最少表达样本过滤不是完全相同的定义，界面参数和导出配置才是本次运行的依据。

自定义热图保留 log2(count+1) 默认。工作台修正了旧脚本子集归一化：log-CPM 用完整文库总量，VST 在完整非零基因矩阵转换后再取目标基因；不会在目标基因子集上重定义库大小。VST 需要唯一 gene_id，不支持无标识地合并 Symbol 后伪装成同一个模型基因。

热图颜色截断只影响显示，CSV 保留未截断矩阵。Pearson 距离=1-r，Ward.D2 只允许欧氏距离。修改 alpha、模型、输入或比较会生成新的模型缓存；改变纯筛选或样式复用基础模型。

## 文件与复现

```text
results/toolbox/
  cache/<模型指纹>.rds
  jobs/<任务ID>/
    inputs/                  本机输入快照与映射
    request.rds              实际参数请求
    parameters.json
    status.json / job.log
    reproduce.R
    working/                 计算中间结果
    outputs/                 下载文件与实际结果
```

绘图默认输出 PNG、SVG、TIFF、PDF 和作图原始数据 CSV；PNG 同时用于界面预览。差异分析本身只输出表，不伪造图像。PCA 同时输出坐标、解释方差和负荷；已绘图的复杂对象另存 bundle.rds。旧热图渲染器通过新的设备接口导出真实四格式，不把 PNG 字节写进 SVG 文件。

结果 ZIP 将图与作图数据放在 `01_图与作图数据`，其余分析结果、注释、参数与日志放在 `02_分析与注释`。Count 输入快照、模型缓存和重绘缓存保存在本地任务目录。复现需要保留代码、输入快照及 R 依赖。源脚本适配器记录脚本 SHA-256。

## 代码结构与原脚本关系

```text
app.R + www/                 交互前端，不计算科学结果
R/toolbox.R                  工具目录、参数、输入检查、任务与下载
toolbox_worker.R             子进程入口，统一状态和错误
R/toolbox_analysis.R         项目输入适配、缓存、任务分派与通用绘图
R/core/analysis/prepare/
  pathways/plots.R           已有模块化科学后端
```

`04.3` 与 `04.4` 在隔离子进程中按 AST 替换明确配置赋值，保留用户原有算法/布局；不会顶层直接 source 后再试图修改已经执行的配置，也不会修改原文件。本次没有覆盖根目录已有未提交的用户脚本改动。

## 检查范围

本次进行源码语法检查、界面启动和 14 个工具面板的浏览器交互检查，并读取分组和执行轻量输入检查。没有点击运行分析，没有拟合真实 Count、联网下载注释或生成新的科研结论。统计结果、完整数据运行和最终科研图验收仍由用户执行。

依赖窗口只报告当前 R 环境的包与版本，不会安装或更新包。Shiny/processx 接口参照官方文档：[runApp](https://shiny.posit.co/r/reference/shiny/latest/runapp.html)、[processx](https://processx.r-lib.org/reference/process.html)。Circos 实现使用 [circlize](https://jokergoo.github.io/circlize_book/book/)。


本次检查范围与边界见 [改版检查记录](validation-2026-11-05.md)，第三方引入与许可证见 [第三方说明](../THIRD_PARTY_NOTICES.md)。
