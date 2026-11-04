# =============================================================================
# 自定义基因 Count 热图
# 功能：只需在下方填写标题、基因列表、Count 文件和分组文件，即可自动识别
#       基因列、样本列及组别，完成表达量转换、行标准化、聚类和热图导出。
# 输入：CSV/TSV 格式的 Count 表 + CSV/TSV 格式的样本分组表。
# 输出：PNG/PDF 热图、实际作图矩阵、基因匹配报告、样本识别报告。
# =============================================================================

# ============================= 1. 用户配置区 =============================
# ---- 1.1 路径、标题和目标基因（通常只需修改这里）----
work_dir <- "C:/Users/86135/Desktop/BioWorkbench"
count_file <- "data/gene_count.csv"            # 可填写相对 work_dir 的路径或绝对路径
group_file <- "data/group.csv"
output_dir <- "04.4_M2_Polarization_Heatmap"
plot_title <- "M1 Associated Gene"
output_prefix <- "Selected_Genes"

# 基因可填写 gene_name 或 gene_id；不区分大小写，未匹配基因会写入报告。
target_genes <- c(
  "Arg1",
  "Mrc1",
  "Retnla",
  "Chil3",
  "Clec10a",
  "Cd163",
  "Il10",
  "Tgfb1"
)

# ---- 1.2 输入列识别 ----
# 设为 NULL 时自动嗅探；如自动识别不正确，可直接填写实际列名。
gene_name_col <- NULL                      # 例如 "gene_name"
gene_id_col <- NULL                        # 例如 "gene_id"
sample_col <- NULL                         # 分组表样本列，例如 "Sample"
group_col <- NULL                          # 分组表组别列，例如 "Group"
gene_name_candidates <- c("gene_name", "gene_symbol", "symbol", "GeneName", "SYMBOL")
gene_id_candidates <- c("gene_id", "GeneID", "ensembl_gene_id", "ID")
sample_col_candidates <- c("Sample", "SampleID", "sample", "sample_id", "ID")
group_col_candidates <- c("Group", "group", "Condition", "condition", "Treatment")
selected_groups <- NULL                    # NULL=使用分组表全部组；也可写 c("M2","HA_CuPB")

# ---- 1.3 Count 过滤、转换和标准化 ----
min_total_count <- 10                      # 每个基因在所选样本中的 Count 总和下限
min_count_in_any_sample <- 1               # 至少一个样本达到的 Count 下限
duplicate_gene_method <- "max_mean"        # 重复基因：max_mean / sum / mean
normalization_method <- "log2"             # log2 / log_cpm / vst / none
pseudo_count <- 1                          # log2(count+pseudo_count)
vst_blind <- TRUE                          # 仅 normalization_method="vst" 时使用
heatmap_scale <- "row"                     # row=逐基因 Z-score；none=不标准化
scale_limit <- 2                           # Z-score 色阶上下限

# ---- 1.4 排序和聚类 ----
preserve_gene_input_order <- FALSE          # TRUE=严格按 target_genes 顺序，不做行聚类
cluster_rows <- TRUE
cluster_columns <- TRUE
cluster_column_slices <- FALSE              # FALSE=只在各组内聚类，不交换组别顺序
row_distance <- "pearson"                  # pearson / spearman / euclidean 等
column_distance <- "pearson"
clustering_method <- "complete"
show_row_dendrogram <- FALSE
show_column_dendrogram <- FALSE

# ---- 1.5 莫兰蒂配色 ----
# 低表达蓝—中间灰粉—高表达粉红，均为低饱和度颜色。
heatmap_colors <- c("#7189B3", "#E7E1E1", "#D9A7AE")
na_color <- "#E5E5E5"
# 分组注释色；组数超过色板长度时自动循环。
morandi_group_palette <- c("#AFC3D8", "#DDB9BC", "#B9C9BE", "#C8BDD2",
                            "#D8C8AD", "#AFC8C9", "#D2BDB3", "#BCC4D6")
group_colors <- c()                        # 可覆盖，如 c(M2="#AFC3D8", HA_CuPB="#DDB9BC")
cell_border_color <- "white"; cell_border_width <- 0.4
row_gap_mm <- 0
column_gap_mm <- 0                       # 组间不额外留白，仅保留与组内一致的单元格边界

# ---- 1.6 所有文字样式 ----
# face 可填写："plain"、"bold"、"italic" 或 "bold.italic"。
# family 可填写系统中已有字体，如 "sans"、"Arial"、"Times New Roman"。
font_family <- "sans"
title_font_size <- 23; title_font_face <- "bold"; title_font_color <- "#111111"
gene_font_size <- 20; gene_font_face <- "bold"; gene_font_color <- "#111111"
sample_font_size <- 15; sample_font_face <- "bold"; sample_font_color <- "#111111"
group_font_size <- 18; group_font_face <- "bold"; group_font_color <- "#111111"
legend_title_font_size <- 18; legend_title_font_face <- "bold"; legend_title_font_color <- "#111111"
legend_label_font_size <- 18; legend_label_font_face <- "bold"; legend_label_font_color <- "#111111"
show_gene_names <- TRUE
show_sample_names <- FALSE                  # FALSE 隐藏 M2_1、HA_CuPB_1 等组内样本名
sample_name_rotation <- 45
show_heatmap_legend <- TRUE
legend_title <- "Z-score"                 # 设为 "" 可隐藏图例标题
legend_bar_width_mm <- 3                   # 图例色条宽度
legend_bar_height_mm <- 20                 # 图例色条高度
legend_at <- c(-2, -1, 0, 1, 2)           # 图例显示的数值；应与 scale_limit 对应

# ---- 1.7 图片导出参数 ----
image_width <- 9                           # 英寸
image_height <- 10                         # 英寸
dpi <- 600
output_formats <- c("png", "pdf")
use_raster <- FALSE                        # FALSE 可减少矢量图色块间的白色细线
# =========================== 用户配置区结束 =============================

options(stringsAsFactors = FALSE)
resolve_path <- function(x) if (grepl("^[A-Za-z]:[/\\\\]", x)) x else file.path(work_dir, x)
read_table_auto <- function(path) {
  if (!file.exists(path)) stop("文件不存在：", path)
  sep <- if (tolower(tools::file_ext(path)) %in% c("tsv", "txt")) "\t" else ","
  read.table(path, header = TRUE, sep = sep, quote = "\"", comment.char = "",
             check.names = FALSE, stringsAsFactors = FALSE)
}
first_hit <- function(x, candidates, label) {
  hit <- candidates[candidates %in% x]
  if (!length(hit)) stop("无法自动识别", label, "；请在顶部直接填写对应列名。")
  hit[1]
}
safe_dist <- function(method) {
  if (method %in% c("pearson", "spearman")) {
    function(m) {
      r <- suppressWarnings(cor(t(m), method = method, use = "pairwise.complete.obs"))
      d <- 1 - r; d[!is.finite(d) | d < 0] <- 0; diag(d) <- 0; as.dist(d)
    }
  } else method
}
scale_rows <- function(m) {
  z <- t(scale(t(m))); z[!is.finite(z)] <- 0
  pmax(pmin(z, scale_limit), -scale_limit)
}

count_path <- resolve_path(count_file); group_path <- resolve_path(group_file)
out_path <- resolve_path(output_dir); dir.create(out_path, recursive = TRUE, showWarnings = FALSE)
counts_df <- read_table_auto(count_path); meta <- read_table_auto(group_path)
gene_name_col <- if (is.null(gene_name_col)) first_hit(names(counts_df), gene_name_candidates, "基因名称列") else gene_name_col
gene_id_col <- if (is.null(gene_id_col)) {
  x <- gene_id_candidates[gene_id_candidates %in% names(counts_df)]; if (length(x)) x[1] else NA_character_
} else gene_id_col
sample_col <- if (is.null(sample_col)) first_hit(names(meta), sample_col_candidates, "样本列") else sample_col
group_col <- if (is.null(group_col)) first_hit(names(meta), group_col_candidates, "分组列") else group_col
if (!all(c(gene_name_col, sample_col, group_col) %in% c(names(counts_df), names(meta)))) stop("配置列名不存在。")

meta[[sample_col]] <- trimws(as.character(meta[[sample_col]])); meta[[group_col]] <- trimws(as.character(meta[[group_col]]))
if (!is.null(selected_groups)) meta <- meta[meta[[group_col]] %in% selected_groups, , drop = FALSE]
group_levels <- if (is.null(selected_groups)) unique(meta[[group_col]]) else selected_groups[selected_groups %in% meta[[group_col]]]
meta[[group_col]] <- factor(meta[[group_col]], levels = group_levels)
meta <- meta[order(meta[[group_col]]), , drop = FALSE]
samples <- as.character(meta[[sample_col]])
missing_samples <- setdiff(samples, names(counts_df))
if (length(missing_samples)) stop("Count 表缺少分组表中的样本列：", paste(missing_samples, collapse = ", "))

counts_df[[gene_name_col]] <- trimws(as.character(counts_df[[gene_name_col]]))
gene_id_value <- if (!is.na(gene_id_col)) trimws(as.character(counts_df[[gene_id_col]])) else rep(NA_character_, nrow(counts_df))
requested <- trimws(as.character(target_genes)); requested <- requested[nzchar(requested)]
key_name <- tolower(counts_df[[gene_name_col]]); key_id <- tolower(gene_id_value)
hit <- key_name %in% tolower(requested) | key_id %in% tolower(requested)
selected <- counts_df[hit, , drop = FALSE]
if (!nrow(selected)) stop("目标基因均未匹配；请检查基因名称或基因 ID。")
mat <- as.matrix(selected[, samples, drop = FALSE]); storage.mode(mat) <- "numeric"
keep <- rowSums(mat, na.rm = TRUE) >= min_total_count & apply(mat, 1, max, na.rm = TRUE) >= min_count_in_any_sample
selected <- selected[keep, , drop = FALSE]; mat <- mat[keep, , drop = FALSE]
if (!nrow(mat)) stop("匹配基因均未通过 Count 过滤阈值。")

# 重复基因处理：默认保留平均 Count 最高的一行；也可按基因求和或均值。
labels <- as.character(selected[[gene_name_col]]); labels[is.na(labels) | !nzchar(labels)] <- gene_id_value[hit][keep][is.na(labels) | !nzchar(labels)]
if (duplicate_gene_method == "max_mean") {
  ord <- order(rowMeans(mat, na.rm = TRUE), decreasing = TRUE); keep_dup <- !duplicated(tolower(labels[ord]))
  ord <- ord[keep_dup]; mat <- mat[ord, , drop = FALSE]; labels <- labels[ord]
} else {
  fun <- if (duplicate_gene_method == "sum") sum else mean
  mat <- do.call(rbind, lapply(split(seq_along(labels), tolower(labels)), function(i) apply(mat[i, , drop = FALSE], 2, fun, na.rm = TRUE)))
  labels <- vapply(split(labels, tolower(labels)), `[`, character(1), 1)
}
rownames(mat) <- labels

if (normalization_method == "log2") norm <- log2(mat + pseudo_count) else if (normalization_method == "log_cpm") {
  lib <- colSums(mat); if (any(lib <= 0)) stop("log_cpm 要求每个样本总 Count > 0。")
  norm <- log2(sweep(mat, 2, lib / 1e6, "/") + pseudo_count)
} else if (normalization_method == "vst") {
  if (!requireNamespace("DESeq2", quietly = TRUE)) stop("VST 需要安装 DESeq2。")
  dds <- DESeq2::DESeqDataSetFromMatrix(round(mat), data.frame(Group = meta[[group_col]], row.names = samples), ~Group)
  norm <- SummarizedExperiment::assay(DESeq2::vst(dds, blind = vst_blind))
} else norm <- mat
plot_mat <- if (heatmap_scale == "row") scale_rows(norm) else norm

# 若要求保留输入顺序，按 target_genes 排列已匹配行，并关闭行聚类。
if (preserve_gene_input_order) {
  rank <- match(tolower(rownames(plot_mat)), tolower(requested)); plot_mat <- plot_mat[order(rank), , drop = FALSE]
  cluster_rows <- FALSE
}
if (!requireNamespace("ComplexHeatmap", quietly = TRUE) || !requireNamespace("circlize", quietly = TRUE))
  stop("请安装 ComplexHeatmap 和 circlize。")
group_values <- levels(meta[[group_col]])
auto_group_colors <- setNames(rep(morandi_group_palette, length.out = length(group_values)), group_values)
if (length(group_colors)) auto_group_colors[intersect(names(group_colors), group_values)] <- group_colors[intersect(names(group_colors), group_values)]
top_anno <- ComplexHeatmap::HeatmapAnnotation(Group = meta[[group_col]], col = list(Group = auto_group_colors),
  show_annotation_name = FALSE, show_legend = FALSE)
col_fun <- circlize::colorRamp2(c(-scale_limit, 0, scale_limit), heatmap_colors)
ht <- ComplexHeatmap::Heatmap(plot_mat, name = legend_title, col = col_fun, na_col = na_color,
  column_split = meta[[group_col]], column_title = group_values, top_annotation = top_anno,
  cluster_rows = cluster_rows, cluster_columns = cluster_columns,
  cluster_column_slices = cluster_column_slices, clustering_method_rows = clustering_method,
  clustering_method_columns = clustering_method, clustering_distance_rows = safe_dist(row_distance),
  clustering_distance_columns = safe_dist(column_distance), show_row_dend = show_row_dendrogram,
  show_column_dend = show_column_dendrogram, show_row_names = show_gene_names,
  show_column_names = show_sample_names, column_names_rot = sample_name_rotation,
  row_names_gp = grid::gpar(fontfamily = font_family, fontsize = gene_font_size, fontface = gene_font_face, col = gene_font_color),
  column_names_gp = grid::gpar(fontfamily = font_family, fontsize = sample_font_size, fontface = sample_font_face, col = sample_font_color),
  column_title_gp = grid::gpar(fontfamily = font_family, fontsize = group_font_size, fontface = group_font_face, col = group_font_color),
  row_gap = grid::unit(row_gap_mm, "mm"), column_gap = grid::unit(column_gap_mm, "mm"),
  rect_gp = grid::gpar(col = cell_border_color, lwd = cell_border_width), use_raster = use_raster,
  show_heatmap_legend = show_heatmap_legend, heatmap_legend_param = list(title = legend_title,
    at = legend_at,
    title_gp = grid::gpar(fontfamily = font_family, fontsize = legend_title_font_size,
      fontface = legend_title_font_face, col = legend_title_font_color),
    labels_gp = grid::gpar(fontfamily = font_family, fontsize = legend_label_font_size,
      fontface = legend_label_font_face, col = legend_label_font_color),
    grid_width = grid::unit(legend_bar_width_mm, "mm"),
    legend_height = grid::unit(legend_bar_height_mm, "mm")))

draw_one <- function(fmt) {
  file <- file.path(out_path, paste0(output_prefix, "_Heatmap.", fmt))
  if (fmt == "pdf") grDevices::pdf(file, image_width, image_height) else grDevices::png(file, image_width, image_height, units = "in", res = dpi)
  ComplexHeatmap::draw(ht, column_title = plot_title,
    column_title_gp = grid::gpar(fontfamily = font_family, fontsize = title_font_size,
      fontface = title_font_face, col = title_font_color), heatmap_legend_side = "right")
  grDevices::dev.off()
}
for (fmt in output_formats) draw_one(fmt)
write.csv(data.frame(Gene = rownames(plot_mat), plot_mat, check.names = FALSE),
  file.path(out_path, paste0(output_prefix, "_PlotMatrix.csv")), row.names = FALSE)
matched_keys <- unique(tolower(c(rownames(plot_mat), gene_id_value[hit][keep])))
match_report <- data.frame(InputGene = requested, Matched = tolower(requested) %in% matched_keys)
write.csv(match_report, file.path(out_path, paste0(output_prefix, "_GeneMatchReport.csv")), row.names = FALSE)
write.csv(meta, file.path(out_path, paste0(output_prefix, "_DetectedSamples.csv")), row.names = FALSE)
message("完成：匹配并绘制 ", nrow(plot_mat), " 个基因；输出目录：", normalizePath(out_path))
