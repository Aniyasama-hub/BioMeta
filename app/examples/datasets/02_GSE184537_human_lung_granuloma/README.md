# GSE184537 — 人肺结核病灶：肉芽肿分区 vs 健康肺实质

**一句话**：同一批病人的肉芽肿中心/内壁/外壁与病灶旁健康肺实质，看病灶内部的空间异质性。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE184537](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE184537) |
| 文献 | PMID 40447570 |
| 平台 | GPL20301 (Illumina HiSeq 4000) |
| 提交时间 | 2025-05 |
| 实验设计 | 手术切除肺标本，按解剖部位分别取肉芽肿三层与健康肺实质 |
| 物种 / 组织 | 人 / lung tissue (TB lesion) |

## 样本构成

共 **48 个样本**，基因 **22,484 个**，中位文库大小 **16,742,191** reads。

| 字段 | 分布 |
|---|---|
| `group` | Granuloma（35）；Healthy parenchyma（13） |
| `drug_sensitivity` | MDR（22）；DS（20）；XDR（6） |
| `relapse` | No（32）；Yes（16） |
| `cavitation` | Cavitation（37）；Tuberculoma（11） |
| `lesion_zone` | External wall（14）；Internal wall（13）；Healthy parenchyma（13）；Center（8） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts_normalized.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。**标准化值，非整数** |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **肉芽肿 vs 健康肺实质**：配对设计（同一 `subject_id`），最干净的病灶 vs 对照。
2. **分区梯度**：Center → Internal wall → External wall，看缺氧、坏死、脂质代谢相关基因的空间变化。
3. **按临床结局分层**：`drug_sensitivity`（MDR/DS/XDR）、`relapse`（复发与否）、`cavitation`（空洞 vs 结核球）。
4. **复发预测特征**：16 例复发 vs 32 例未复发，可做表达特征与复发的关联。

## 注意

- ⚠️ 矩阵是**标准化表达值（非整数）**，文件名为 `counts_normalized.tsv.gz`，不能跑 edgeR/DESeq2 的负二项模型，只能做表达量比较或 limma。
- 同一病人多个部位样本，统计时要用配对/混合效应模型，不能当独立样本。
- `group` 列是组织部位（Granuloma / Healthy parenchyma）；`disease_state` 全是 TB。

## 读入示例

```r
counts <- read.delim(gzfile('counts_normalized.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：Granuloma 相对 Healthy parenchyma。
- 方法：limma（log2 CPM，源数据没有原始整数 Count）。
- 样本：保留 26/48 个与示例比较相符的样本。
- 表达矩阵：排除 1 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~subject_id + condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
