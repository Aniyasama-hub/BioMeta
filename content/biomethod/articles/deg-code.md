## 定义解释

这篇把“读 Count → 定义比较 → 拟合 DESeq2 → 导出完整表 → 筛选候选”逐行展开。前面的 DEG 介绍负责解释怎么读结果，这里看每一步怎样落在 R 里。

本文配合 [方法介绍](/biomethod/articles/deg) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

例如处理与对照的归一化均值分别为 100 和 50，简单 log2 比值为 1。模型还会结合重复波动估计效应与标准误，再生成 P 值和 BH 调整值。对比向量固定为 treated 相对 control。

<figure class="bm-process"><figcaption>例子：变化幅度和稳定程度要一起看</figcaption><ol><li><strong>确认方向</strong><span>比较“处理 / 对照”，对照均值 50，处理均值 100。</span></li><li><strong>衡量幅度</strong><span>归一化表达的简单比值为 2，log2 比值为 1。</span></li><li><strong>估计不确定性</strong><span>结合各重复的波动和离散度，拟合计数模型并检验。</span></li><li><strong>校正与筛选</strong><span>保存全部结果，再按事先确定的 padj 与 |log2FC| 阈值筛选。</span></li></ol></figure>

## 分析操作

### 先准备输入

`counts.csv` 和 `samples.csv` 的列约定与标准化技术帖一致。基因编号和样本名唯一；`condition` 使用 control、treated。安装 DESeq2，先检查原始计数和实验设计。

### 第一步：输入、过滤与拟合

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

### 第二步：提取对比并保存结果

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

`alpha` 也参与 DESeq2 的独立过滤选择，`lfc_cutoff` 在这里用于结果筛选。批次可按实际设计加入公式，例如 `~ batch + condition`；需要先保证条件与批次能够分别估计。

### 输出怎样核对

核对 `deg_all.csv` 的样本比较方向、基因数量、缺失原因和已知成员表达。`deg_selected.csv` 是筛选产物；GSEA 排序从完整有效统计值出发。保留 `stat`、`pvalue`、`padj` 和效应量，便于后续复核。

## 适用范围

示例覆盖两组独立样本。配对、交互与连续变量需要相应设计和对比；正式分析结合模型诊断，记录过滤规则和版本。

## 参考与致谢

参考 DESeq2 原始论文与官方教程。感谢 DESeq2 作者和维护者。
