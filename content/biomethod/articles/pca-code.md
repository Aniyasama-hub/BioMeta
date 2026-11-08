## 定义解释

这里接住 PCA 介绍中拆出的两个代码例子：先复现四个点的手算，再从已有 VST 表导出实际坐标与图。两部分各自运行，后面会重新建立 PCA 对象。

本文配合 [方法介绍](/biomethod/articles/pca) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

在四点例子里，B 始终等于 2A。中心化后，第一方向可以写成约 (0.447,0.894)，S1 得分约 −4.472。R 可能把方向整体取反，检查点间距离和解释方差即可对照同一几何关系。

<figure class="bm-process"><figcaption>例子：同一张矩阵怎样得到坐标与图片</figcaption><ol><li><strong>整理矩阵</strong><span>四个样本分别是 (1,2)、(2,4)、(4,8)、(5,10)。</span></li><li><strong>中心化</strong><span>两列均值为 3 和 6；S1 变成 (−2,−4)。</span></li><li><strong>计算投影</strong><span>沿约 (0.447,0.894) 的单位方向，S1 坐标约为 −4.472。</span></li><li><strong>导出</strong><span>保存坐标、负荷和解释方差，再用同一结果画四种格式。</span></li></ol></figure>

## 分析操作

### 先准备输入

第一部分直接使用代码里的四点矩阵。第二部分准备 vst.csv，首列名为 gene_id，其余样本列为已处理的有限数值；可额外有 gene_name 列。VST 的生成见标准化技术帖。基础 PCA 和四种导出使用 R 自带 stats 与 grDevices。

### 第一部分：逐行复现手算

```r
toy <- rbind(S1 = c(1, 2), S2 = c(2, 4), S3 = c(4, 8), S4 = c(5, 10)) # 四行是样本，两列是特征。
colnames(toy) <- c("A", "B") # 给两列特征命名。
centered <- scale(toy, center = TRUE, scale = FALSE) # 各列减去自己的均值，保留原有尺度。
pca <- prcomp(toy, center = TRUE, scale. = FALSE) # 用 SVD 计算主成分。
print(centered) # 查看 A 均值为 3、B 均值为 6 时的中心化结果。
print(pca$x) # 查看样本在各主成分上的坐标。
print(pca$rotation) # 查看定义新方向的特征权重。
print(pca$sdev^2 / sum(pca$sdev^2) * 100) # 计算各轴的解释方差百分比。
```

### 第二部分：从 VST 表到坐标和四种图片

```r
setwd("C:/my_analysis") # 改成存放 vst.csv 的目录。
output_dir <- "pca_results" # 输出文件夹名称。
dir.create(output_dir, showWarnings = FALSE) # 创建输出目录。
pca_top_genes <- 500 # 最多纳入的高变基因数，可按研究问题调整。
scale_genes <- FALSE # TRUE 时按基因标准差缩放，FALSE 保留各基因原有波动尺度。
show_labels <- TRUE # 是否显示样本名称。
point_size <- 1.5 # 基础绘图中点的相对大小。
figure_width <- 7 # 画布宽度，单位英寸。
figure_height <- 6 # 画布高度，单位英寸。
dpi <- 300 # 位图分辨率，单位像素每英寸。
formats <- c("png", "svg", "tiff", "pdf") # 同一份坐标导出的四种图像格式。
expression_table <- read.csv("vst.csv", check.names = FALSE) # 读取基因 × 样本的 VST 表。
sample_columns <- setdiff(names(expression_table), c("gene_id", "gene_name")) # 从样本列中排除基因标识与名称列。
expression <- as.matrix(expression_table[, sample_columns, drop = FALSE]) # 组合样本表达矩阵。
rownames(expression) <- expression_table$gene_id # 用 gene_id 标识每一行。
stopifnot(is.numeric(expression), all(is.finite(expression))) # 表达列必须是有限数值。
stopifnot(!anyDuplicated(rownames(expression))) # 基因编号必须唯一。
variances <- apply(expression, 1, var) # 计算各基因的跨样本方差。
valid <- names(variances)[is.finite(variances) & variances > 0] # 排除常数或无效方差的特征。
selected <- head(valid[order(variances[valid], decreasing = TRUE)], pca_top_genes) # 按方差选前 N 个有效基因。
stopifnot(length(selected) >= 2, ncol(expression) >= 3) # 此处的二维展示至少保留两个特征与三个样本。
pca <- prcomp(t(expression[selected, , drop = FALSE]), center = TRUE, scale. = scale_genes) # 转为样本 × 基因后中心化并计算。
stopifnot(ncol(pca$x) >= 2) # 后面的 PC1、PC2 图需要两个坐标列。
coordinates <- data.frame(sample_id = rownames(pca$x), pca$x) # 把样本名称与坐标放进同一张表。
explained <- pca$sdev^2 / sum(pca$sdev^2) * 100 # 用各轴方差除以总方差。
write.csv(coordinates, file.path(output_dir, "sample_coordinates.csv"), row.names = FALSE) # 保存作图坐标。
write.csv(data.frame(PC = seq_along(explained), explained_percent = explained), file.path(output_dir, "explained_variance.csv"), row.names = FALSE) # 保存解释方差。
write.csv(data.frame(gene_id = rownames(pca$rotation), pca$rotation), file.path(output_dir, "gene_loadings.csv"), row.names = FALSE) # 保存基因负荷。
write.csv(data.frame(gene_id = selected, expression[selected, , drop = FALSE]), file.path(output_dir, "plot_expression.csv"), row.names = FALSE) # 保存实际参与计算的表达数据。
for (format in formats) { # 依次导出四种格式，复用同一份 PCA 结果。
  path <- file.path(output_dir, paste0("pca.", format)) # 组合当前图片的路径。
  switch(format, # 按格式打开对应的 R 图形设备。
    png = png(path, width = figure_width, height = figure_height, units = "in", res = dpi), # PNG 按英寸和分辨率导出。
    svg = svg(path, width = figure_width, height = figure_height), # SVG 保存矢量图。
    tiff = tiff(path, width = figure_width, height = figure_height, units = "in", res = dpi, compression = "lzw"), # TIFF 使用 LZW 压缩。
    pdf = pdf(path, width = figure_width, height = figure_height)) # PDF 保存矢量页面。
  plot(coordinates$PC1, coordinates$PC2, pch = 16, cex = point_size, col = "#5B6B70", # 用 PC1、PC2 坐标画散点。
       xlab = sprintf("PC1 (%.1f%%)", explained[1]), ylab = sprintf("PC2 (%.1f%%)", explained[2])) # 在轴标题标出解释方差。
  if (show_labels) text(coordinates$PC1, coordinates$PC2, labels = coordinates$sample_id, pos = 3, cex = 0.7) # 在点上方写样本名。
  dev.off() # 关闭当前设备，将图片写入文件。
} # 完成全部格式的图片导出。
writeLines(capture.output(sessionInfo()), file.path(output_dir, "sessionInfo.txt")) # 保存 R 版本与软件环境。
```

### 分组颜色怎样接入

这里先用同一种点色看计算。需要按组着色时，按样本 ID 将分组表匹配到坐标表，再设置颜色。`center`、`scale.` 与高变基因数影响分析；字号、点大小和画布尺寸影响展示。

### 对应当前工作站的哪一步

当前计算由 `prepare_bundle` 准备数据，绘图层使用已经生成的坐标。下面的源码索引可核对项目实现；教程按独立 R 操作组织。若分享某次完整任务，连同导出的 R、输入文件和参数一起提供。

### 输出怎样核对

坐标表的行数应等于样本数，负荷表行数应等于入选特征数，解释方差合计约为 100%。抽查 plot_expression.csv 的成员是否与所选基因数一致，再检查 PNG、SVG、TIFF、PDF 的图轴与标签。

## 适用范围

第二部分用于已有 VST 或适当连续矩阵的 PCA。原始 Count 先完成对应模型和变换；常数矩阵或维度不足的输入需要先处理。

## 参考与致谢

参考 R prcomp 官方文档、PCA 综述与 DESeq2 教程。感谢相关方法及软件作者。
