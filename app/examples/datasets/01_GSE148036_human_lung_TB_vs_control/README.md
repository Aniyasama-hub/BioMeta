# GSE148036 — 人肺组织：结核 vs 正常肺 / 腺癌 / 结节病

**一句话**：唯一一个「整块人肺组织 + 非感染对照」的数据集，用来回答结核肺里哪些基因真的变了。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE148036](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE148036) |
| 文献 | PMID 33097805 |
| 平台 | GPL21290 (Illumina NovaSeq 6000) |
| 提交时间 | 2020-10 |
| 实验设计 | 手术/活检肺组织 bulk RNA-seq，四组平行 |
| 物种 / 组织 | 人 / lung tissue |

## 样本构成

共 **20 个样本**，基因 **17,493 个**，中位文库大小 **18,011,469** reads。

| 字段 | 分布 |
|---|---|
| `group` | Normal（5）；TB（5）；Adenocarcinoma（5）；Sarcoidosis（5） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。整数，原始 count |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **TB vs Normal**：最直接的验证——你的候选基因在结核肺组织里是否上调/下调。
2. **TB vs 腺癌 / 结节病**：排除「只要是肺病就会变」的非特异基因，只留下结核特异的。
3. **细胞类型去卷积**（CIBERSORTx / xCell）：估计巨噬细胞 M1/M2 比例，与你的极化假设对接。
4. **通路水平验证**：把你的铜死亡/金属稳态基因集做 ssGSEA，看是否在 TB 组整体偏移。

## 注意

- 每组只有 5 例，差异分析的统计功效有限，`p` 值要谨慎解读。
- 腺癌与结节病是对照疾病，不是同类感染，比较时别当成「疾病组」。
- `sample_id`（NM001/TB001/AD001/SA001）本身就编码了分组，可直接解析。

## 读入示例

```r
counts <- read.delim(gzfile('counts.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：TB 相对 Normal。
- 方法：DESeq2（原始整数计数）。
- 样本：保留 10/20 个与示例比较相符的样本。
- 表达矩阵：排除 0 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
