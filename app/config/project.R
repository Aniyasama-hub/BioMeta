# 所有相对路径相对于本配置文件；源文件只读，结果另存。
# 先用已有小鼠整数 Count 接通下游；FASTQ 定量完成后切换 mode="salmon"。
config <- list(
  project = list(id = "mouse_polarization", species = "Mus_musculus",
                 output = "../../results/cli", max_samples = 30L),
  input = list(
    mode = "counts", samples = "samples.csv",
    counts = "../../data/gene_count.csv",
    genes = NULL, gene_id_col = "gene_id", gene_name_col = "gene_name",
    salmon_dir = "../data/salmon", tx2gene = "../references/tx2gene.csv",
    reference_manifest = "../references/reference_manifest.json"
  ),
  analysis = list(
    condition_levels = c("M2", "HA@CuPB"), # 保留原分组名；对照在前。
    use_batch = FALSE,                 # 至少两个技术批次时启用；不把时间点当批次。
    covariates = character(0),         # 如 "timepoint"；必须与样本表列名一致。
    min_count = 10L,                   # 原始 Count 下限，调高可去除弱表达基因。
    min_samples = 3L,                  # 至少几个样本达到 min_count；常取最小组重复数。
    size_factor_type = "ratio",       # DESeq2 ratio；大量零值时可评估 poscounts。
    fit_type = "parametric",          # 离散度拟合 parametric/local/mean。
    alpha = 0.05,                      # results 独立过滤的目标 FDR，改变需重算结果。
    independent_filtering = TRUE,
    cooks_cutoff = TRUE,               # 保留离群值处理；NA 原因单独导出。
    vst_blind = FALSE,                 # 用设计估计组内变异，不意味着去批次。
    batch_visualization = FALSE,       # 可视化矩阵去技术批次，绝不回输差异模型。
    shrink = "none",                  # none/normal；收缩另存，不覆盖原始 log2FC。
    seed = 1L
  ),
  contrast = list(numerator = "HA@CuPB", denominator = "M2"), # 正值为HA@CuPB高。
  selection = list(
    padj_cutoff = 0.05, log2fc_cutoff = 1, # FDR<0.05 且 |log2FC|>=1，即至少两倍。
    direction = "all",                  # all/up/down；共享于DEG、热图及ORA。
    label_top_n = 0L,                    # 火山图每方向标注数量；0 不显示标签。
    lfc_column = "log2FoldChange",       # 可改 log2FC_shrunken；图上明确记录列名。
    pca_top_genes = 500L, pca_scale = FALSE,
    use_batch_visualization = FALSE,
    heatmap_mode = "deg",               # deg/variable/custom。
    heatmap_top_n = 50L,                 # 候选基因按padj排序或按方差选取。
    target_genes = "target_genes.csv",   # custom时用；GeneKey可为稳定ID或Symbol。
    row_zscore = TRUE,                  # 每基因样本间相对表达；不比较不同基因绝对量。
    cluster_rows = TRUE, cluster_columns = FALSE,
    distance = "pearson",               # pearson或euclidean；常数行将被去除并记录。
    linkage = "complete",               # complete/average/ward.D2；Ward要求欧氏距离。
    pathway_top_n = 15L, pathway_id = NULL
  ),
  pathways = list(
    enabled = character(0),             # 可填 ora/gsea/gsva/ppi；按需检查依赖。
    gmt = NULL, gmt_id_type = "SYMBOL",  # 固定本地GO/KEGG等GMT及其来源/版本。
    database_label = "local_GMT", database_version = "UNSET",
    min_size = 10L, max_size = 500L,
    ora_padj = 0.05, gsea_padj = 0.05, seed = 1L,
    ppi_edges = NULL, ppi_score = 0.7     # CSV from/to为gene_id，score必须0~1。
  ),
  style = list(
    palette = c("#7897B8", "#D99A9F", "#A9B8A5", "#B4A6BC",
                "#D8C5A5", "#9FB8B6", "#C7B5A8", "#ADB2BE"),
    group_colors = c(M2 = "#7897B8", "HA@CuPB" = "#D99A9F"), # 莫兰迪蓝灰/豆沙。
    colors = c(Up = "#D99A9F", Down = "#7897B8", Not_significant = "#BEBBBA"),
    low = "#7897B8", mid = "#F3F0EB", high = "#D99A9F",
    width = 10, height = 8,              # 画布尺寸，单位英寸；字挤时优先增大画布。
    dpi = 300, base_size = 16,           # 位图dpi；base_size单位pt。
    point_size = 3, point_alpha = 0.8, label_size = 4,
    z_limit = 2,                         # 只截断显示色阶，不修改保存的Z-score。
    legend_position = "right", show_gene_names = TRUE,
    show_sample_labels = TRUE, formats = c("png", "svg", "tiff", "pdf")
  )
)
