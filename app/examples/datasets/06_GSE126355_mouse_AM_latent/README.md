# GSE126355 — 小鼠肺泡巨噬细胞：潜伏感染与再攻击

**一句话**：LTBI 模型小鼠的肺泡巨噬细胞，看潜伏状态下巨噬细胞的基线状态和再感染反应。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE126355](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE126355) |
| 文献 | PMID 32673357 |
| 平台 | GPL19057 (Illumina NextSeq 500) |
| 提交时间 | 2020-06 |
| 实验设计 | C57BL/6 低剂量感染建立潜伏模型，分选肺泡巨噬细胞，含 H37Rv 再攻击 |
| 物种 / 组织 | 小鼠 / alveolar macrophage |

## 样本构成

共 **12 个样本**，基因 **11,671 个**，中位文库大小 **22,153,837** reads。

| 字段 | 分布 |
|---|---|
| `group` | ltbi / naive（5）；cntl / naive（3）；ltbi / mEmNeg（2）；ltbi / mEmPos（2） |
| `timepoint` | 0（6）；24（6） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。整数，原始 count |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **潜伏 vs 对照**：`ltbi / naive`(5) vs `cntl / naive`(3)，看潜伏期 AM 的基础转录状态。
2. **再攻击应答**：`mEmPos` / `mEmNeg` 两组，对应再感染后的不同表型。
3. **与人的 AM 数据对照**（03）：保守的巨噬细胞应答模块。

## 注意

- 每组只有 2–5 例，只能看趋势，不适合报严格的 `p` 值。
- 细胞是分选后的肺泡巨噬细胞，不是全肺，看不到上皮/间质信号。
- `timepoint` 是感染时间（0 / 24），单位见原文。

## 读入示例

```r
counts <- read.delim(gzfile('counts.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：ltbi / naive 相对 cntl / naive。
- 方法：DESeq2（原始整数计数）。
- 样本：保留 8/12 个与示例比较相符的样本。
- 表达矩阵：排除 0 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
