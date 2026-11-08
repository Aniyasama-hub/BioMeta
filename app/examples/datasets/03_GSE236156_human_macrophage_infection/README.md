# GSE236156 — 人肺泡巨噬细胞 / 单核来源巨噬细胞：体外感染 Mtb

**一句话**：人原代肺泡巨噬细胞感染结核分枝杆菌后的转录组，最贴近「巨噬细胞怎么应答结核菌」。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE236156](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE236156) |
| 文献 | PMID 38464296; 39162406; 41208107 |
| 平台 | GPL24676 (Illumina NovaSeq 6000) |
| 提交时间 | 2024-03 |
| 实验设计 | 原代肺泡灌洗液 AM 与血单核来源 MDM，体外感染 Mtb 或干扰素刺激 |
| 物种 / 组织 | 人 / BAL / blood (macrophage) |

## 样本构成

共 **57 个样本**，基因 **13,699 个**，中位文库大小 **20,019,472** reads。

| 字段 | 分布 |
|---|---|
| `group` | Media（20）；M. tuberculosis（15）；IFNA8（5）；IFNb（5）；IFNe（5）；IFNg（5）；（2） |
| `cell_type` | monocyte-derived macrophage（37）；alveolar macrophage（18）；（2） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。整数，原始 count |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **Mtb vs Media**：AM 与 MDM 分开做，再比较两类巨噬细胞的应答差异。
2. **干扰素对照**：`IFNA8/IFNb/IFNe/IFNg` 四组可判断你的基因是不是 IFN 通路驱动——若你的基因在 IFN 组也变，说明是通用抗病毒/炎症反应而非 Mtb 特异。
3. **跨物种对照**：与小鼠 AM 数据（06、08）比较，看哪些应答是保守的。
4. **极化标志物**：M1（NOS2、IL1B、CXCL9/10）与 M2（MRC1、CD163、ARG1）比值。

## 注意

- 体外体系、单一时间点（具体感染时长见原文方法），不等于体内肺组织。
- AM（18 例）与 MDM（37 例）样本量不等，别把两类细胞混在一个模型里。
- `group` = 处理条件；`cell_type` 区分 AM / MDM；`subject_id` 是供者编号。

## 读入示例

```r
counts <- read.delim(gzfile('counts.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：M. tuberculosis 相对 Media。
- 方法：DESeq2（原始整数计数）。
- 样本：保留 14/57 个与示例比较相符的样本。
- 表达矩阵：排除 29 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~subject_id + condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
