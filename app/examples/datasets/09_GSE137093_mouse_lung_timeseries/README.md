# GSE137093 — 小鼠全肺时间序列：HN878 / H37Rv 两种菌株

**一句话**：两种临床菌株、高低剂量、感染后 26–56 天的全肺转录组，时间维度最完整的一组。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE137093](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE137093) |
| 文献 | PMID 32205882 |
| 平台 | GPL21103 (Illumina HiSeq 4000) |
| 提交时间 | 2020-01 |
| 实验设计 | C57BL/6 低/高剂量气溶胶感染 HN878 或 H37Rv，多时间点取全肺 |
| 物种 / 组织 | 小鼠 / whole lung |

## 样本构成

共 **88 个样本**，基因 **21,614 个**，中位文库大小 **188,878** reads。

| 字段 | 分布 |
|---|---|
| `group` | HN878（38）；Uninfected（30）；H37Rv（20） |
| `timepoint` | day26（30）；day42（30）；day56（10）；day33（5）；day32（5）；day40（5）；day35（3） |
| `strain` | HN878（38）；Uninfected（30）；H37Rv（20） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts_normalized.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。**标准化值，非整数** |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **时间进程**：感染 vs 未感染，沿 day26 → day42 → day56 看基因表达轨迹（cluster 随时间变化的模式）。
2. **菌株差异**：HN878（高毒、W-Beijing 系）vs H37Rv，找菌株特异的宿主反应。
3. **剂量效应**：高剂量 vs 低剂量。
4. **与 B6 其他模型对照**（07、08）：同品系不同感染模型的共性与差异。

## 注意

- ⚠️ 矩阵是 **DESeq2 标准化值**，文件名为 `counts_normalized.tsv.gz`，不是原始 count。
- 时间点不均匀：day26 与 day42 各 30 例，day56 仅 10 例，另有 day32/33/35/40 少量；做时间趋势要按实际分布处理。
- 矩阵列名 `GRA502Axxx` 到 GSM 的映射已放在 `group.tsv` 的 `gsm` 列。

## 读入示例

```r
counts <- read.delim(gzfile('counts_normalized.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：HN878 相对 Uninfected。
- 方法：limma（log2 CPM，源数据没有原始整数 Count）。
- 样本：保留 30/88 个与示例比较相符的样本。
- 表达矩阵：排除 0 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
