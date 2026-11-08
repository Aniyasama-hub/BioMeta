## 定义解释

本篇先用十个背景基因手算超几何尾概率，再用完整 DEG 和成员关系表演示 ORA。GO / KEGG 的来源、分类和界面操作留在方法介绍里。

本文配合 [方法介绍](/biomethod/articles/go-kegg) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

背景 10 个基因，其中 4 个属于通路；候选 3 个，全部命中。随机抽取时至少命中 3 个的概率为 C(4,3)/C(10,3)=1/30。若同时检验多个通路，把它们的 P 值放在一起做 BH 调整。

<figure class="bm-process"><figcaption>例子：候选集里出现 3 个通路成员，有多突出？</figcaption><ol><li><strong>确定背景</strong><span>10 个可受检、可匹配基因，其中 4 个属于通路 P。</span></li><li><strong>圈出候选</strong><span>按同一规则选出 3 个候选，3 个都属于 P。</span></li><li><strong>计算尾概率</strong><span>随机抽 3 个全命中的概率：C(4,3) / C(10,3) = 1/30。</span></li><li><strong>一起校正</strong><span>若还检验其他通路，对全部受检通路的 P 值做 BH 校正。</span></li><li><strong>回看成员</strong><span>查看这 3 个基因的方向、表达和证据，再组织生物学解释。</span></li></ol></figure>

## 分析操作

### 先准备输入

手算部分可直接运行。文件部分需要 DESeq2 风格的完整 deg_all.csv，含 gene_id、pvalue、padj、log2FoldChange；term2gene.tsv 含 term_id、gene 两列，gene 与 gene_id 使用同一编号。成员表可从对应公共资源或 GMT 整理而来，保留物种和版本。安装 clusterProfiler。

### 第一步：看清单个通路的概率

```r
N <- 10 # 受检且能匹配注释的背景基因数。
K <- 4 # 背景中属于这条通路的基因数。
n <- 3 # 候选基因数。
k <- 3 # 候选里命中这条通路的基因数。
p <- phyper(k - 1, K, N - K, n, lower.tail = FALSE) # 求 P(X≥k)，结果约为 0.0333。
print(p) # 查看这条通路的原始尾概率。
print(p.adjust(c(p, 0.2, 0.8), method = "BH")) # 以三条通路为例做 BH 调整，第一项变为约 0.1。
```

### 第二步：从完整差异表形成背景与候选

```r
setwd("C:/my_analysis") # 改成存放输入表的目录。
library(clusterProfiler) # 加载通用富集分析接口。
deg <- read.csv("deg_all.csv", check.names = FALSE) # 读取完整差异表。
members <- read.delim("term2gene.tsv", colClasses = "character") # 读取两列的通路成员关系。
stopifnot(!anyDuplicated(deg$gene_id)) # 完整表中每个基因保持唯一。
members <- unique(members[c("term_id", "gene")]) # 仅保留去重后的通路—基因关系。
tested <- deg$gene_id[is.finite(deg$pvalue)] # 用有效原始 P 值识别本例的受检范围。
background <- intersect(tested, members$gene) # 形成受检且可匹配的背景。
alpha <- 0.05 # 候选基因要求 padj 小于此显著性阈值。
lfc_cutoff <- 1 # 候选基因的绝对 log2FC 下限。
keep <- !is.na(deg$padj) & deg$padj < alpha & abs(deg$log2FoldChange) >= lfc_cutoff # 同时应用显著性与幅度条件。
selected <- intersect(deg$gene_id[which(keep)], background) # 候选限制在同一背景内。
min_size <- 10 # 匹配背景后允许的最小集合大小。
max_size <- 500 # 匹配背景后允许的最大集合大小。
ora <- enricher(selected, universe = background, TERM2GENE = members, # 指定候选、背景和成员关系。
                pAdjustMethod = "BH", pvalueCutoff = 1, qvalueCutoff = 1, # 先保留宽阈值结果，随后筛选展示。
                minGSSize = min_size, maxGSSize = max_size) # 过滤过小或过大的集合。
write.csv(as.data.frame(ora), "ora_results.csv", row.names = FALSE) # 保存通路统计表。
write.csv(data.frame(gene_id = background), "ora_background.csv", row.names = FALSE) # 保存实际背景。
write.csv(data.frame(gene_id = selected), "ora_candidates.csv", row.names = FALSE) # 保存实际候选。
writeLines(capture.output(sessionInfo()), "sessionInfo.txt") # 记录软件环境。
```

公共 GO 的 BP、CC、MF 在工作站分别检验和校正；若用上面的通用接口复现分类结果，先按对应类别拆分成员表，再分别调用。KEGG 使用对应物种的成员映射。候选筛选列与缺失值处理也要和实际设置对应。

### 输出怎样核对

先数背景与候选，再抽查命中成员。结果中的 GeneRatio、BgRatio 分别描述候选和背景的成员比例。原始 P、BH 调整值与展示顺序分别记录；共享成员较多的通路一起解释。

## 适用范围

文件示例展示使用 padj 与幅度双条件的 ORA。若研究使用单条件筛选、其他统计列或单方向候选，按预设规则更改相关步骤。实际工作站的完整列选择和审核逻辑可在源码索引核对。

## 参考与致谢

参考 GO 富集说明、KEGG 官方资料和 clusterProfiler 文档。感谢资源与软件维护者。
