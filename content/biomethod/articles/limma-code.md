## 定义解释

这篇把连续 log2 表达值的两组比较展开：读表、设计、拟合、对比、经验贝叶斯、完整结果导出。每个模型对象都对应一个明确步骤。

本文配合 [方法介绍](/biomethod/articles/limma) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

例如对照均值为 4、处理均值为 5，设计和对比会提取处理减对照的系数 1。经验贝叶斯再参考整批基因的方差信息，帮助稳定检验使用的标准误。

<figure class="bm-process"><figcaption>例子：把组间差异与重复的波动分开看</figcaption><ol><li><strong>读入连续表达</strong><span>某基因对照为 4.0、4.2、3.8，处理为 5.0、5.2、4.8。</span></li><li><strong>拟合组均值</strong><span>在线性模型里估计对照均值 4、处理均值 5。</span></li><li><strong>提取对比</strong><span>在 log2 尺度上，处理 − 对照 = 1。</span></li><li><strong>借助整体信息</strong><span>经验贝叶斯结合全体基因的方差，稳定各基因的标准误。</span></li><li><strong>整理统计表</strong><span>导出 logFC、检验统计量、P 值与 BH 调整值。</span></li></ol></figure>

## 分析操作

### 先准备输入

安装 limma。log2_expression.csv 第一列为基因编号，其余列为已适当处理的连续 log2 表达；samples.csv 第一列为样本名，condition 为 control 或 treated。下面使用独立两组设计。

### 第一步：对齐输入并建立设计

```r
setwd("C:/my_analysis") # 改成输入文件所在目录。
library(limma) # 加载线性模型和经验贝叶斯方法。
expression <- as.matrix(read.csv("log2_expression.csv", row.names = 1, check.names = FALSE)) # 读取基因 × 样本矩阵。
samples <- read.csv("samples.csv", row.names = 1) # 读取样本和分组。
samples <- samples[colnames(expression), , drop = FALSE] # 按表达列名对齐分组。
stopifnot(identical(rownames(samples), colnames(expression))) # 确认每个表达列有对应分组。
stopifnot(is.numeric(expression), all(is.finite(expression))) # 输入表达值保持有限数值。
samples$condition <- factor(samples$condition, levels = c("control", "treated")) # 指定两组的名称和顺序。
design <- model.matrix(~ 0 + condition, samples) # 为每组分别估计均值系数。
colnames(design) <- levels(samples$condition) # 将系数名简化成 control、treated。
stopifnot(qr(design)$rank == ncol(design)) # 设计中的系数需要可分别估计。
```

### 第二步：拟合、比较和输出

```r
fit <- lmFit(expression, design) # 对每个基因拟合相同设计的线性模型。
contrast <- makeContrasts(treated - control, levels = design) # 指定处理相对对照的比较。
fit <- contrasts.fit(fit, contrast) # 将组系数转换成指定对比。
fit <- eBayes(fit) # 结合跨基因信息调整残差方差并计算检验。
result <- topTable(fit, coef = 1, number = Inf, adjust.method = "BH", sort.by = "none") # 保留全部基因并做 BH 校正。
result <- data.frame(gene_id = rownames(result), result) # 将基因编号放入独立列。
write.csv(result, "limma_all.csv", row.names = FALSE) # 导出完整效应量和显著性结果。
write.csv(data.frame(sample_id = rownames(design), design), "design.csv", row.names = FALSE) # 保存实际设计矩阵。
writeLines(capture.output(sessionInfo()), "sessionInfo.txt") # 记录 R 与 limma 版本。
```

### 对应项目中的使用位置

内置 log2 CPM 示例的准备脚本使用 limma 建立差异表，具体数据读取与元数据整理见下方源码索引。GSVA 的组间比较也用线性模型，但输入改为通路评分，结果要按评分差解释。若增加配对或批次，先修改设计与对比，再检查设计矩阵。

### 输出怎样核对

核对 design.csv 中样本顺序与组编码；确认正 logFC 对应 treated 较高。比较原始表达与系数方向，再结合 adj.P.Val 及波动解释。

## 适用范围

用于已适当处理的连续 log2 表达。原始 Count 的 voom 方案还需要均值—方差权重步骤；输入和参数按对应官方方案设置。

## 参考与致谢

参考 limma 方法论文与官方用户指南。感谢 limma 和原数据研究团队。
