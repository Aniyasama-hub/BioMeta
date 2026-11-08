# GSE193979 — 人全血：抗结核治疗随访（诊断 / 2 周 / 2 月 / 6 月）

**一句话**：同一批病人四个时间点的配对转录组，用来验证「治疗过程中表达是否回落」。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE193979](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE193979) |
| 文献 | PMID 35841871 |
| 平台 | GPL18573 (Illumina NextSeq 500) |
| 提交时间 | 2022-08 |
| 实验设计 | 多中心前瞻队列（印尼、南非），全血 PAXgene，诊断至治疗 6 月连续采样 |
| 物种 / 组织 | 人 / whole blood |

## 样本构成

共 **87 个样本**，基因 **15,415 个**，中位文库大小 **10,933,417** reads。

| 字段 | 分布 |
|---|---|
| `group` | TB-IH（67）；TB-preDM（20） |
| `timepoint` | Month_6（23）；Diagnosis（23）；Month_2（21）；Week_2（20） |
| `disease_category` | TB-IH（67）；TB-preDM（20） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。整数，原始 count |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **治疗前后配对比较**：`subject_id` 可配对，四时间点做趋势检验，找随治疗恢复正常的基因。
2. **基线特征验证**：诊断时 vs 健康对照的表达特征，与你其他数据集的活动性 TB 特征做一致性检验。
3. **治疗应答异质性**：2 周/2 月时仍不回落 vs 快速回落的病人，看基线差异。
4. **代谢合并症影响**：`TB-IH`（中间高血糖）vs `TB-preDM`（糖尿病前期）。

## 注意

- ⚠️ 只覆盖 **87/231** 个样本：GEO 的合并矩阵列名（RSEQ 编号）与 GSM 完全对不上，能可靠映射的只有 RAW.tar 里这 87 个。
- 组别只有 TB-IH 与 TB-preDM，**缺纯 TB 与 TB-DM**（这两组在无法映射的 148 个样本里）；要补齐需从 SRA 下 FASTQ 重新定量。
- 中位测序深度 10.9M，低于其他数据集，做低表达基因时要更保守。

## 读入示例

```r
counts <- read.delim(gzfile('counts.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：TB-preDM 相对 TB-IH。
- 方法：DESeq2（原始整数计数）。
- 样本：保留 23/87 个与示例比较相符的样本。
- 表达矩阵：排除 0 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
