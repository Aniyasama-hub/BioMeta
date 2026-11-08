## 定义解释

这里逐行把完整差异统计表变成有名称的排序向量，读取 GMT，运行 fgsea 并保存曲线和结果。先看排序对象怎样建立，再看每个参数作用在哪。

本文配合 [方法介绍](/biomethod/articles/gsea) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

例如 A、C 在六个基因的排序中位于第 1 和第 3 位，等权重累计会在第 3 位升到 0.75。正式计算使用设置的统计量权重，并通过零分布估计显著性。输入里的正方向决定正 NES 的含义。

<figure class="bm-process"><figcaption>例子：六个基因里的命中位置怎样变成曲线</figcaption><ol><li><strong>排好顺序</strong><span>A、B、C、D、E、F，从正向到负向；集合为 A、C。</span></li><li><strong>遇到成员就上升</strong><span>用等权重演示：命中加 1/2，未命中减 1/4。</span></li><li><strong>逐步累计</strong><span>累计值依次为 0.5、0.25、0.75、0.5、0.25、0。</span></li><li><strong>找偏离并评估</strong><span>最大偏离为 0.75；正式分析结合统计量权重与零分布得到 ES、NES 和显著性。</span></li></ol></figure>

## 分析操作

### 先准备输入

准备完整 deg_all.csv，至少含唯一 gene_id 与有方向的 stat；若含 pvalue，也保留有效原始值。my_sets.gmt 的成员使用相同 gene_id。计算安装 fgsea，曲线导出安装 ggplot2 和 SVG 设备依赖 svglite；以下例子在 ID 命名空间直接分析。

### 第一步：整理完整有效排名

```r
setwd("C:/my_analysis") # 改成存放差异表和 GMT 的目录。
library(fgsea) # 加载预排序富集方法。
deg <- read.csv("deg_all.csv", colClasses = c(gene_id = "character")) # 把基因编号按文字读取。
valid <- !is.na(deg$gene_id) & nzchar(deg$gene_id) & is.finite(deg$stat) # 保留有编号和有限统计量的记录。
if ("pvalue" %in% names(deg)) valid <- valid & is.finite(deg$pvalue) # 若提供原始 P 值，保留有效受检记录。
deg <- deg[valid, , drop = FALSE] # 形成完整有效范围。
deg <- deg[order(-abs(deg$stat), deg$gene_id), , drop = FALSE] # 为重复编号按绝对统计量确定保留顺序。
deg <- deg[!duplicated(deg$gene_id), , drop = FALSE] # 同一排名编号只保留一条记录。
ranks <- sort(setNames(deg$stat, deg$gene_id), decreasing = TRUE) # 构造有名称、从大到小的统计向量。
pathways <- gmtPathways("my_sets.gmt") # 每行 GMT 转成一个有名称的基因集合。
min_size <- 10 # 与排名匹配后允许的最小成员数。
max_size <- 500 # 与排名匹配后允许的最大成员数。
weight <- 1 # 命中权重指数，1 表示按统计量绝对值加权。
```

### 第二步：计算并保存结果

```r
set.seed(2026) # 固定随机种子，记录本次随机计算起点。
result <- fgseaMultilevel(pathways = pathways, stats = ranks, # 使用完整排名与成员集合。
                         minSize = min_size, maxSize = max_size, gseaParam = weight) # 设置有效大小和命中权重。
saveRDS(result, "gsea_results.rds") # 保留包括 leadingEdge 列表在内的完整 R 对象。
table <- as.data.frame(result) # 生成便于写入 CSV 的副本。
table$leadingEdge <- vapply(table$leadingEdge, paste, character(1), collapse = ";") # 把每条通路的核心成员合为一格。
write.csv(table, "gsea_results.csv", row.names = FALSE) # 保存全部计算结果供筛选。
write.csv(data.frame(gene_id = names(ranks), stat = ranks), "gsea_ranks.csv", row.names = FALSE) # 保留实际输入排序。
writeLines(capture.output(sessionInfo()), "sessionInfo.txt") # 保存 R 和包版本。
```

### 第三步：选择一条已计算通路导出曲线

先在结果表里选好要看的 pathway，替换下面的集合 ID。

```r
library(ggplot2) # 加载通用图像导出函数。
target <- "MY_SET_V1" # 替换为本次结果表中实际存在的 pathway。
stopifnot(target %in% result$pathway) # 确认该集合通过大小过滤并有计算结果。
plot <- plotEnrichment(pathways[[target]], ranks, gseaParam = weight) # 使用同一排名与权重生成富集曲线。
for (format in c("png", "svg", "tiff", "pdf")) { # 逐一保存四种图像格式。
  ggsave(paste0("gsea_curve.", format), plot, width = 7, height = 5, dpi = 300) # 画布单位为英寸，位图分辨率为 300 dpi。
} # 完成当前集合的导出。
```

若 GMT 用 SYMBOL，而结果表使用其他 gene_id，先用可追溯的映射生成相同命名空间的排名。重复 SYMBOL 的保留规则也要记录；当前工作站使用绝对统计量最大的记录，并输出映射报告。

### 输出怎样核对

确认排序长度、有效集合大小、NES 方向与核心成员。CSV 便于查看，RDS 保留列表结构。绘图和计算保持相同 gseaParam，记录随机种子及版本。

## 适用范围

适合完整预排序分析。教程采用直接 gene_id 匹配；公共资源下载、跨编号映射与工作站任务管理在运行工具中完成。

## 参考与致谢

参考 GSEA 原始论文和 fgsea 官方教程。感谢 GSEA、fgsea 与实际基因集的作者和维护者。
