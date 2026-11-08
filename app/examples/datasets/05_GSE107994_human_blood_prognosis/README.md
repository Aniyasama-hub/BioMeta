# GSE107994 — 人全血：潜伏感染者的预后（谁进展为活动性结核）

**一句话**：LTBI 随访队列，有 23 例后来进展成活动性结核，用来做预后/预测验证。

## 数据来源

| 项 | 内容 |
|---|---|
| GEO 编号 | [GSE107994](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE107994) |
| 文献 | PMID 29921861 |
| 平台 | GPL20301 (Illumina HiSeq 4000) |
| 提交时间 | 2018-04 |
| 实验设计 | 英国 Leicester 队列，活动性 TB、LTBI、健康对照及 LTBI 进展者，含纵向随访 |
| 物种 / 组织 | 人 / whole blood |

## 样本构成

共 **175 个样本**，基因 **17,284 个**，中位文库大小 **21,638,197** reads。

| 字段 | 分布 |
|---|---|
| `group` | Active_TB（53）；Control（50）；LTBI（49）；LTBI_Progressor（23） |
| `timepoint` | Baseline（160）；≤0.5_Active_TB_diagnosed（5）；0.6-2.5（3）；2.6-3.3（2）；3.4-5.0_Active_TB_diagnosed（2）；2.6-3.3_Active_TB_diagnosed（1）；≤0.5（1）；0.6-2.5_Active_TB_diagnosed（1） |

## 文件说明

| 文件 | 内容 |
|---|---|
| `counts.tsv.gz` | 基因 × 样本表达矩阵。行名是 gene symbol，列名是 `sample_id`（与 `group.tsv` 对应）。整数，原始 count |
| `group.tsv` | 样本注释。`sample_id` 对应表达矩阵列名，`group` 是主分组，其余为临床/实验字段 |
| `log2cpm.tsv.gz` | log2(CPM+1)，用于 PCA、热图、样本相关性、跨数据集比较 |
| `sample_qc.tsv` | 每个样本的文库大小、检出基因数、QC 标记 |

## 可以做什么分析

1. **诊断分类**：Active_TB vs Control / LTBI，评估候选基因的区分能力（ROC）。
2. **进展预测**：LTBI_Progressor（23）vs LTBI（49），这是核心——你的基因能否在发病前就区分出来。
3. **个体轨迹**：15 例非基线随访样本，按 `subject_id` 看同一个体随时间的变化。
4. **与肺组织结果对照**：血液里变的方向是否与肺组织一致（一致才说明是可检测的外周标志）。

## 注意

- 血液反映外周免疫状态，不等于肺局部；与肺组织数据（01、02）结论不一致是正常的。
- Progressor 仅 23 例，任何预测模型都必须做交叉验证，别用全数据调参再报 AUC。
- `outlier_flag` 列来自原文献的质控标记，建模前建议先剔除 `Yes`。
- `timepoint` 是随访月数分组，160 例为 Baseline。

## 读入示例

```r
counts <- read.delim(gzfile('counts.tsv.gz'), row.names = 1, check.names = FALSE)
group  <- read.delim('group.tsv', stringsAsFactors = FALSE)
stopifnot(all(colnames(counts) == group$sample_id))
```

## 工作站默认示例

- 比较：Active_TB 相对 Control。
- 方法：DESeq2（原始整数计数）。
- 样本：保留 91/175 个与示例比较相符的样本。
- 表达矩阵：排除 0 个空 ID、非有限值或全零行。保留 0 个重复符号行，并用后缀区分。
- 差异结果仅供流程演示。

- 低表达过滤：至少 3 个样本 Count 达到 10；模型显著性 0.05，离散度拟合 parametric（仅 Count 示例）。
- 模型设计：~condition。完整 DEG 保留未显著基因供 GSEA 排序使用。
- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。
- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。
