## 定义解释

这篇把成员 CSV 转成 GMT，并用实际 Tab 拆开文件，检查集合和表达数据能匹配多少成员。适合成员较多、希望反复维护自定义集合的读者。

本文配合 [方法介绍](/biomethod/articles/gmt) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

例如长表里有 P—A、P—B、Q—B 三行，按集合分组后，P 行放 A、B，Q 行放 B。若表达表只有 A、C，P 匹配 1 个，Q 匹配 0 个。下面先写文件，再单独输出有效成员计数。

<figure class="bm-process"><figcaption>例子：把整理好的成员清单变成可用的 GMT</figcaption><ol><li><strong>定义问题</strong><span>先写清物种、编号类型、入选证据和基因集版本。</span></li><li><strong>整理长表</strong><span>每行记一个“集合—基因”关系；保留来源并处理重复。</span></li><li><strong>横向排成一行</strong><span>每个集合一行：集合 ID → 描述 → 基因 1 → 基因 2 → ……</span></li><li><strong>保存为 GMT</strong><span>字段之间用 Tab，行与行之间换行，文件使用 UTF-8。</span></li><li><strong>核对有效成员</strong><span>和表达表匹配后再数基因数；确认物种、编号和分析阈值。</span></li></ol></figure>

## 分析操作

### 先准备输入

先按 [GMT 构建教程](/biomethod/articles/gmt) 下载并填写 CSV 草表，另存 gene-set-members.csv。至少保留 set_id、description、gene_id、species、evidence 五列，同一集合的描述一致；全表使用同一物种和编号类型。代码使用 R 自带函数。

### 第一步：读取长表并检查字段

```r
setwd("C:/my_analysis") # 改成成员整理表所在目录。
members <- read.csv("gene-set-members.csv", colClasses = "character", check.names = FALSE, fileEncoding = "UTF-8") # 将所有编号作为文字读入。
required <- c("set_id", "description", "gene_id", "species", "evidence") # 定义整理表需要的字段。
stopifnot(all(required %in% names(members)), nrow(members) > 0) # 确认表头和非空记录。
members[required] <- lapply(members[required], trimws) # 清理字段前后的空白。
stopifnot(!anyNA(members[required])) # 缺失信息先回到整理表补全。
stopifnot(all(nzchar(members$set_id)), all(nzchar(members$gene_id))) # 集合和基因编号必须填写。
stopifnot(length(unique(members$species)) == 1, all(nzchar(members$species))) # 本次文件统一为一个明确物种。
stopifnot(!any(grepl("[\t\r\n]", as.matrix(members[c("set_id", "description", "gene_id")])))) # 字段内部避免 Tab 和换行。
members$description[!nzchar(members$description)] <- "na" # 空描述补成一个有效占位字段。
sets <- split(members, members$set_id) # 将同一集合的记录放在一起。
stopifnot(all(vapply(sets, function(x) length(unique(x$description)) == 1, logical(1)))) # 每个集合只对应一个描述。
```

### 第二步：按集合合并为 GMT 行

```r
lines <- vapply(sets, function(x) { # 逐个集合构造一行。
  genes <- unique(x$gene_id) # 合并同一集合内部的重复成员。
  paste(c(x$set_id[1], x$description[1], genes), collapse = "\t") # ID、描述和成员之间写入真正的 Tab。
}, character(1)) # 每个集合返回一个字符行。
writeLines(enc2utf8(lines), "my_sets_v1.gmt", useBytes = TRUE) # 按 UTF-8 字节保存 GMT。
write.csv(members, "members_audit_v1.csv", row.names = FALSE) # 另存成员证据与物种记录。
writeLines(capture.output(sessionInfo()), "sessionInfo.txt") # 保存用于构建的 R 环境。
```

`collapse = "\t"` 会写入制表符。长表保留证据与物种，GMT 每行保留集合 ID、描述和成员，二者一起维护。

### 第三步：重新读入，核对成员数

```r
fields <- strsplit(readLines("my_sets_v1.gmt", encoding = "UTF-8"), "\t", fixed = TRUE) # 按真正的 Tab 拆开每行。
stopifnot(all(lengths(fields) >= 3)) # 每行至少有 ID、描述和一个成员。
set_ids <- vapply(fields, `[`, character(1), 1) # 提取每行的集合 ID。
stopifnot(!anyDuplicated(set_ids)) # 一个文件内集合 ID 保持唯一。
pathways <- setNames(lapply(fields, function(x) unique(x[-c(1, 2)])), set_ids) # 还原去重后的成员列表。
sizes <- data.frame(set_id = names(pathways), original_size = lengths(pathways)) # 汇总每个集合写入的成员数。
write.csv(sizes, "gmt_set_sizes.csv", row.names = FALSE) # 导出集合大小表。
```

### 第四步：与实际表达数据匹配

另准备 expression_genes.csv，其中 gene_id 一列来自本次表达表，使用和 GMT 相同的编号。

```r
expression_genes <- read.csv("expression_genes.csv", colClasses = "character") # 读取本次检测到的基因编号。
universe <- unique(expression_genes$gene_id) # 合并重复的表达编号。
matched <- lapply(pathways, intersect, y = universe) # 逐集合寻找实际可用成员。
sizes$matched_size <- lengths(matched) # 记录匹配后的大小。
sizes$missing_genes <- vapply(pathways, function(x) paste(setdiff(x, universe), collapse = ";"), character(1)) # 列出未匹配成员便于排查。
write.csv(sizes, "gmt_matching_report.csv", row.names = FALSE) # 保存原始大小、有效大小和缺失成员。
```

### 输出怎样核对

用文本编辑器打开 my_sets_v1.gmt，再抽查一个集合是否与长表一致。gmt_matching_report.csv 若显示大量丢失，先核对物种与编号，再确定分析大小阈值。零匹配集合应在来源或输入层面找原因。

## 适用范围

适合统一物种、统一编号的成员长表。收集成员的科学依据、跨物种转换和别名歧义，需要在构建文件之前整理，保留证据表与修改记录。

## 参考与致谢

格式依据 GSEA / MSigDB 官方文档。感谢基因集资源整理者与 R 维护者。
