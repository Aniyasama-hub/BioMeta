## 定义解释

本篇从已下载的 Reactome All Levels 表出发，解释怎样选物种、保留来源、映射编号并整理为可用于构建 GMT 的长表。

本文配合 [方法介绍](/biomethod/articles/reactome) 阅读。代码按输入、处理、输出分段，每行右侧的注释说明这一步在做什么。运行前在 RStudio 选择需要的 R 版本，安装列出的包，并把工作目录改成自己的文件夹。

## 分析原理

例如上级通路 P 包含 A、B、C，其中 B 还属于子通路 P1。成员表里保留 P—B 和 P1—B 两条关系；集合内部的同一条关系去重。原始来源与映射表一起留存，便于追溯层级与编号转换。

<figure class="bm-process"><figcaption>例子：同一批成员，按研究问题选择用法</figcaption><ol><li><strong>查看层级</strong><span>设子通路 P1 含 A、B，子通路 P2 含 B、C。</span></li><li><strong>保留成员关系</strong><span>较大的上级通路 P 含 A、B、C；B 可以同时出现在多个集合。</span></li><li><strong>匹配研究数据</strong><span>若表达表有 A、B、D，可参与的 P 成员为 A、B。</span></li><li><strong>选择分析</strong><span>问“偏在排序哪端”用 GSEA；问“每个样本的评分”用 GSVA；看表达模式用注释热图。</span></li></ol></figure>

## 分析操作

### 先准备输入

从 [Reactome 官方下载目录](https://reactome.org/download/current/NCBI2Reactome_All_Levels.txt) 下载同名文件并记录日期和资源版本。该表依次为 Entrez、通路 ID、URL、名称、证据、物种六列。以下以人类 SYMBOL 为输出，安装 AnnotationDbi 和 org.Hs.eg.db。

### 第一步：读取六列映射并选人类

```r
setwd("C:/my_analysis") # 改成官方映射文件所在目录。
library(AnnotationDbi) # 加载基因编号查询接口。
library(org.Hs.eg.db) # 加载当前 R 环境的人类编号注释。
raw <- read.delim("NCBI2Reactome_All_Levels.txt", header = FALSE, colClasses = "character", quote = "") # 按字符读取官方制表符文件。
stopifnot(ncol(raw) == 6) # 核对当前下载文件的六列结构。
names(raw) <- c("entrez", "set_id", "url", "label", "evidence", "species") # 给官方字段赋予可读列名。
human <- raw[raw$species == "Homo sapiens", , drop = FALSE] # 只保留人类条目。
mapping <- select(org.Hs.eg.db, keys = unique(human$entrez), keytype = "ENTREZID", columns = "SYMBOL") # 将官方 Entrez 成员查询为 SYMBOL。
write.csv(mapping, "reactome_id_mapping.csv", row.names = FALSE) # 保留完整编号查询结果，检查一对多与缺失。
```

### 第二步：整理成员与来源

```r
joined <- merge(human, mapping, by.x = "entrez", by.y = "ENTREZID", all.x = TRUE) # 将原成员与编号映射关联。
write.csv(joined, "reactome_mapping_audit.csv", row.names = FALSE) # 保存映射前后的名称、证据和未匹配记录。
matched <- joined[!is.na(joined$SYMBOL) & nzchar(joined$SYMBOL), , drop = FALSE] # 取有可用 SYMBOL 的关系。
members <- unique(data.frame(set_id = matched$set_id, description = matched$url, # 将稳定 ID 和来源链接放在独立列。
                             gene_id = matched$SYMBOL, species = matched$species, evidence = matched$evidence)) # 保留成员、物种与证据。
write.csv(members, "gene-set-members.csv", row.names = FALSE) # 输出 GMT 构建教程接受的长表。
writeLines(capture.output(sessionInfo()), "sessionInfo.txt") # 保存本机注释包版本。
```

### 第三步：检查歧义，再转换 GMT

先查看 reactome_id_mapping.csv 中同一 Entrez 的多条记录、缺失 SYMBOL 和重复名称，按预定规则处理并记录。确认后使用 [GMT 构建代码](/biomethod/articles/gmt-code) 转换长表。若选择保留 Entrez，则沿用官方成员编号，并让表达数据转换到相同编号体系。

工作站公共注释模块还会根据当前输入产生映射审计、缓存和来源记录，具体实现见下面源码索引。

### 输出怎样核对

检查输出是否只有目标物种，集合 ID 是否符合该物种前缀，随机抽几条成员回查官方来源。获取时间、Reactome 发行版本和本机 org.Hs.eg.db 版本分别记录。匹配后的有效成员数以本次表达数据为准。

## 适用范围

示例针对人类与指定官方六列文件。小鼠使用相应物种和注释包；同源推断内容结合条目证据解读。

## 参考与致谢

参考 Reactome 资源论文、官方下载说明与 AnnotationDbi 文档。感谢相关策展者与软件维护者。
