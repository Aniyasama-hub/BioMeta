# GSE232922 — 小鼠全肺：Sp140 缺失与遗传易感

**一句话**：Sp140 敲除 vs B6 全肺，感染 25 天后看遗传易感基因如何改变肺内免疫状态。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE232922](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE232922) |
| 文献 | PMID 38029747 |
| 平台 | GPL17021 (Illumina HiSeq 2500) |
| 提交时间 | 2024-01 |
| 实验设计 | Sp140 KO 与 B6 对照，pDC-DTR 清除与否，Mtb 感染 Day 25 全肺 |
| 物种 / 组织 | 小鼠 / whole lung |

## 样本构成

共 **24 个样本**，基因 **15,262 个**，中位文库大小 **24,430,620** reads。

| 字段 | 分布 |
|---|---|
| `group` | Sp140 KO / plus（7）；Sp140 KO / minus（6）；B6 / minus（6）；B6 / plus（5） |
| `genotype` | Sp140 KO（13）；B6（11） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。整数，原始 count |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **Sp140 KO vs B6**（取 `pdc_dtr = minus` 组）：易感基因缺失后的基线转录改变。
2. **pDC 清除效应**：DTR+ vs DTR−，判断表型是否依赖 pDC。
3. **与人群数据对照**：SP140 是克罗恩病/结核易感位点，可与人肺组织结果互证。

## 注意

- ⚠️ 矩阵列名 `DK1–DK24` 是按 GSM 升序对应的（已验证一致），不要改动列顺序。
- 每组 5–7 例，统计功效有限。
- `group` = 基因型 / pDC 清除状态组合。

## 读入示例

```r
counts <- read.delim(gzfile('counts.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：Sp140 KO / minus 相对 B6 / minus。
- 方法：DESeq2（原始整数计数）。
- 样本：保留 12/24 个与示例比较相符的样本。
- 表达矩阵：排除 1 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~batch + condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
