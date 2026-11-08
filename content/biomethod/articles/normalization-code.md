## 定义解释

这里从 Count 表出发，逐行生成大小因子、归一化计数、VST 和按行缩放矩阵。每张表都保留基因和样本名称，便于看清数值从哪一步开始改变。

本文配合 [方法介绍](/biomethod/articles/normalization) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

例如原始计数 100、200，大小因子为 1、2 时，归一化后都是 100；若一行展示值是 2、4、6，按行缩放后为 −1、0、1。下面分别实现这两类处理，并把 VST 单独保存。

<figure class="bm-process"><figcaption>例子：同一条基因，先统一尺度，再看变化</figcaption><ol><li><strong>原始计数</strong><span>样本 A 为 100，样本 B 为 200。</span></li><li><strong>校正测序量</strong><span>假设大小因子分别为 1 和 2，归一化后都是 100。</span></li><li><strong>准备展示矩阵</strong><span>用 VST 缓解均值与方差的关系，供 PCA 等探索。</span></li><li><strong>按行显示</strong><span>另一行值为 2、4、6：均值 4，样本标准差 2，Z 值为 −1、0、1。</span></li></ol></figure>

## 分析操作

### 先准备输入

`counts.csv` 第一列为唯一基因编号，其余列为非负整数计数；`samples.csv` 第一列为样本名，`condition` 列使用 `control` 与 `treated`。当前示例使用两组独立样本。先安装 DESeq2，并确认有足够的生物学重复。

### 第一步：读取并拟合计数模型

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

同一组内的重复波动会参与离散度估计。若有批次或配对，先根据设计修改样本信息与模型公式，并检查变量可区分。

### 第二步：分别导出各个阶段

```r
write.csv(data.frame(sample_id = names(sizeFactors(dds)), size_factor = sizeFactors(dds)), "size_factors.csv", row.names = FALSE) # 保存每个样本的大小因子。
normalized <- counts(dds, normalized = TRUE) # 除以大小因子，保留计数尺度的归一化值。
vst_matrix <- assay(varianceStabilizingTransformation(dds, blind = FALSE)) # 使用已有设计的离散度信息做方差稳定化。
write.csv(data.frame(gene_id = rownames(normalized), normalized, check.names = FALSE), "normalized_counts.csv", row.names = FALSE) # 用 gene_id 列保存基因编号。
write.csv(data.frame(gene_id = rownames(vst_matrix), vst_matrix, check.names = FALSE), "vst.csv", row.names = FALSE) # 导出可接入 PCA 教程的 VST 表。
row_sd <- apply(vst_matrix, 1, sd) # 为每个基因计算跨样本标准差。
variable <- vst_matrix[is.finite(row_sd) & row_sd > 0, , drop = FALSE] # 排除无法计算 Z 值的常数行。
row_z <- t(scale(t(variable))) # 转置后按列缩放，再转回基因 × 样本方向。
write.csv(data.frame(gene_id = rownames(row_z), row_z, check.names = FALSE), "row_z.csv", row.names = FALSE) # 保存基因编号与行内相对高低。
writeLines(capture.output(sessionInfo()), "sessionInfo.txt") # 记录 R 与依赖包版本。
```

### 输出怎样核对

大小因子一行一个样本；另外三张表均为基因 × 样本。抽查同一基因在各表的变化，Z 值各行均值约为零。VST 使用已有设计信息，展示矩阵中的批次模式仍需要单独评估。CSV 第一列名为 gene_id，可直接接入 PCA 教程，也可在工作站指定为基因编号列。

## 适用范围

适用于与 DESeq2 假设相符的原始计数。教程使用完整的方差稳定化函数，适合看清步骤；批次调整、复杂设计和模型诊断按实际研究补充。

## 参考与致谢

参考 DESeq2 原始论文与官方教程。感谢 DESeq2 维护者。
