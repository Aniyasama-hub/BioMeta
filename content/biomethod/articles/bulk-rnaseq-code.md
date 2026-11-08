## 定义解释

本篇用一条最小的 Count → 模型 → VST → PCA → DEG 路线解释数据怎样流动，再把功能分析链接到各自的技术帖。工作站中的审核和绘图操作可以按方法介绍完成。

本文配合 [方法介绍](/biomethod/articles/bulk-rnaseq) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

例如 6 个样本先对应分组，再由同一份计数模型得到差异表和 VST。PCA 使用 VST 里的高变基因，差异比较使用计数模型。两种输出有同一份样本身份，分别用于整体探索和逐基因检验。

<figure class="bm-process"><figcaption>例子：从 6 个样本走到一个可追溯的功能线索</figcaption><ol><li><strong>整理输入</strong><span>3 个对照 + 3 个处理，Count 列名与分组表逐一对应。</span></li><li><strong>检查样本</strong><span>PCA 里某个处理样本偏远，先核对标签和测序质量。</span></li><li><strong>比较表达</strong><span>确认样本后比较处理相对对照，保留全部基因的统计结果。</span></li><li><strong>解释功能</strong><span>把候选基因放回受检背景，查看哪些功能成员较集中。</span></li><li><strong>保存依据</strong><span>同时留下输入、参数、版本、统计表和图，方便复核。</span></li></ol></figure>

## 分析操作

### 先准备输入

准备 counts.csv、samples.csv，样本名与 condition 约定见 [DESeq2 技术帖](/biomethod/articles/deg-code)。安装 DESeq2。以下各段按顺序在同一 R 会话执行。

### 第一步：整理输入并建立模型

```r
setwd("C:/my_analysis") # 改成存放输入文件的工作目录。
library(DESeq2) # 加载计数模型与 VST 所需的包。
count_table <- read.csv("counts.csv", row.names = 1, check.names = FALSE) # 第一列作为基因编号。
counts <- as.matrix(count_table) # 将样本计数列整理为数值矩阵。
samples <- read.csv("samples.csv", row.names = 1, check.names = FALSE) # 第一列为样本名，condition 为组别。
samples <- samples[colnames(counts), , drop = FALSE] # 按计数矩阵列名对齐样本信息。
stopifnot(identical(rownames(samples), colnames(counts))) # 样本名必须逐项一致。
samples$condition <- factor(samples$condition, levels = c("control", "treated")) # 固定对照和处理的顺序。
min_count <- 10 # 低表达过滤的计数下限，可按研究设计调整。
min_samples <- 3 # 至少有多少个样本达到计数下限。
counts <- counts[rowSums(counts >= min_count) >= min_samples, , drop = FALSE] # 保留达到过滤规则的基因。
dds <- DESeqDataSetFromMatrix(counts, samples, design = ~ condition) # 为两组独立样本建立计数模型。
dds <- DESeq(dds) # 估计大小因子、离散度并拟合模型。
```

### 第二步：输出探索矩阵与 PCA 坐标

```r
vst_matrix <- assay(varianceStabilizingTransformation(dds, blind = FALSE)) # 生成基因 × 样本的探索矩阵。
write.csv(data.frame(gene_id = rownames(vst_matrix), vst_matrix, check.names = FALSE), "vst.csv", row.names = FALSE) # 保存可接入 PCA 教程的基因编号和表达矩阵。
variances <- apply(vst_matrix, 1, var) # 计算每个基因在各样本间的方差。
top_genes <- 500 # 最多选择多少个高变基因。
ranked <- order(variances, decreasing = TRUE) # 按方差从大到小排列。
selected <- head(ranked[is.finite(variances[ranked]) & variances[ranked] > 0], top_genes) # 选取有效的高变基因。
pca <- prcomp(t(vst_matrix[selected, , drop = FALSE]), center = TRUE, scale. = FALSE) # 转为样本 × 特征后计算 PCA。
write.csv(data.frame(sample_id = rownames(pca$x), pca$x), "pca_coordinates.csv", row.names = FALSE) # 导出每个样本的坐标。
```

### 第三步：保存完整差异结果与候选

```r
alpha <- 0.05 # 多重校正后的显著性筛选阈值。
lfc_cutoff <- 1 # 候选基因的绝对 log2 倍数变化下限。
result <- results(dds, contrast = c("condition", "treated", "control"), alpha = alpha) # 提取处理相对对照的模型比较。
deg <- data.frame(gene_id = rownames(result), as.data.frame(result)) # 把基因编号加入明确的数据列。
write.csv(deg, "deg_all.csv", row.names = FALSE) # 保存全部基因，包含缺失统计值。
selected <- deg[!is.na(deg$padj) & deg$padj < alpha & abs(deg$log2FoldChange) >= lfc_cutoff, ] # 按显著性与幅度筛选候选。
write.csv(selected, "deg_selected.csv", row.names = FALSE) # 另存候选集用于后续讨论。
writeLines(capture.output(sessionInfo()), "sessionInfo.txt") # 保存运行环境。
```

### 第四步：按研究问题接下游

需要画 PCA，接 [PCA 导出教程](/biomethod/articles/pca-code)；查看候选功能，接 [ORA 教程](/biomethod/articles/go-kegg-code)；用完整排序寻找集合信号，接 [GSEA 教程](/biomethod/articles/gsea-code)。自己整理集合时接 [GMT 构建教程](/biomethod/articles/gmt)。每一步都核对编号和输入范围。

### 输出怎样核对

确认 PCA 坐标一行一个样本，VST 列顺序与样本表一致，DEG 方向为 treated / control。结果表、参数与输入一起保存；下游方法按各自需要读取完整表或候选表。

## 适用范围

用于理解独立两组 Count 分析的计算顺序。需要批次、配对或其他协变量时，先修改设计；完整图形导出、功能分析和数据映射分别见关联技术帖。

## 参考与致谢

参考 DESeq2 与 R stats 的官方资料。感谢各软件维护者。
