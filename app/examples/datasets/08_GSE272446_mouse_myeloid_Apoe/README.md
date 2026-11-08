# GSE272446 — 小鼠髓系细胞：Apoe 缺失与感染后 10/28 天

**一句话**：Apoe 缺失 vs B6，感染后 10 天与 28 天，分选 AM / MDM / 中性粒细胞的转录组。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE272446](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE272446) |
| 文献 | PMID 40523023 |
| 平台 | GPL24247 (Illumina NovaSeq 6000) |
| 提交时间 | 2025-06 |
| 实验设计 | Apoe KO 与 B6，Mtb 感染，分选三类髓系细胞，两个时间点 |
| 物种 / 组织 | 小鼠 / alveolar macrophage / MDM / neutrophil |

## 样本构成

共 **41 个样本**，基因 **15,822 个**，中位文库大小 **13,809,606** reads。

| 字段 | 分布 |
|---|---|
| `group` | uninfected（24）；Mtb infected（17） |
| `timepoint` | 28（24）；10（17） |
| `cell_type` | MDM（18）；Neut（12）；AM（11） |
| `genotype` | Apoe（21）；B6（20） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。整数，原始 count |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **感染 vs 未感染**（按细胞类型分层）：AM / MDM / 中性粒细胞各自的感染应答。
2. **Apoe 效应**：脂代谢基因缺失如何改变抗菌与炎症程序。
3. **时间进程**：Day 10 vs Day 28，看从急性到慢性的转变。
4. **中性粒细胞**：结核病理中 PMN 的促炎/损伤作用。

## 注意

- 原矩阵的 `NA` 已按未检出处理为 0；这会略微低估缺失值的影响。
- GEO 未提供 GSM 号，`group.tsv` 的 `gsm` 列为空，样本标识用 `sample_id`。
- 三类细胞功能差异大，**不要合并成一个矩阵做差异分析**。

## 读入示例

```r
counts <- read.delim(gzfile('counts.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：Apoe 相对 B6。
- 方法：DESeq2（原始整数计数）。
- 样本：保留 5/41 个与示例比较相符的样本。
- 表达矩阵：排除 364 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
