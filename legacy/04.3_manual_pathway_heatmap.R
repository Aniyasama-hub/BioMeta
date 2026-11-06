# 手工通路注释热图：只读取用户填写的Excel，不联网、不执行GO/KEGG富集
# ============================== 用户配置区 ==============================
work_dir <- "."
expression_file <- "inputs/expression.csv"
metadata_file <- "inputs/groups.csv"; manual_annotation_file <- "inputs/annotation.xlsx"
output_dir <- "04.3_Manual_Pathway_Heat_after"; project_name <- "Manual_Pathway"
sample_id_col <- "Sample"; group_col <- "Group"; selected_groups <- c("Control", "Treatment")
gene_id_col <- "gene_id"; gene_label_col <- "gene_name"; organism <- "mmu"

filter_mode <- "top"                        # top/threshold/custom/all
padj_col <- "padj"; log2fc_col <- "log2FC"; padj_cutoff <- 0.05; log2fc_cutoff <- 1
min_total_count <- 10; top_n_genes <- 30; max_genes <- 100; custom_genes <- c()
include_all_annotated_genes <- TRUE
include_unannotated_top_genes <- FALSE
show_all_gene_pathways <- TRUE
exclude_manual_other <- TRUE
normalization_method <- "vst"               # vst/log_cpm/log2/none
heatmap_scale <- "row"; scale_limit <- 2; pseudo_count <- 1 # 热图色阶固定为-2～2

auto_pathway_annotation <- FALSE; use_go <- FALSE; use_kegg <- FALSE
enrich_p_cutoff <- 0.10; enrich_q_cutoff <- 0.20; min_pathway_genes <- 2
target_keywords <- c()
keyword_score_bonus <- 2; target_excel_bonus <- 5; target_pathways_only <- TRUE
unassigned_process <- "Other"; process_order <- NULL
# Excel的GeneAnnotation表：GeneKey,Pathway,Database,PathwayID,Use；逐基因手工结果优先
# Excel的TargetPathways表：Database,PathwayID,PathwayName,Priority,Use；用于提升/限定目标通路

cluster_within_process <- TRUE; cluster_columns <- TRUE
distance_rows <- "pearson"; distance_columns <- "pearson"; clustering_method <- "complete"
order_pathways_by_direction <- TRUE          # Treatment-up blocks first, Control-high blocks last
pathway_direction_cutoff <- 0.25             # mean row-Z difference used for Up/Mixed/Down label
order_genes_by_direction <- TRUE             # within each pathway: Treatment-up, mixed, then Control-up
gene_direction_cutoff <- 0.15                # row-Z mean difference defining gene direction
cluster_on_group_means <- TRUE               # stabilize row ordering against replicate-level noise
group_mean_distance <- "euclidean"           # distance used on the group-mean ordering matrix
# Layout: no extra slice gap; thin white borders create equal spacing within/between pathways.
row_gap_mm <- 0; column_gap_mm <- 0; annotation_gap_mm <- 0
cell_border_color <- "white"; cell_border_width <- 0.5
use_raster_heatmap <- FALSE                 # vector cells avoid hairline seams in PDF/PNG
show_row_dendrogram <- FALSE; show_column_dendrogram <- FALSE

# Exact blue-neutral-pink palette sampled from the supplied reference figure.
heatmap_colors <- c("#3E6AAE", "#E5DEDE", "#DFB1BB")
na_color <- "#E5E5E5"

# Light muted pathway palette sampled directly from the supplied reference figure.
morandi_process_palette <- c(
  "#BCCEE6", "#F3E5D2", "#F0CDCD", "#DDEBE7", "#CFDBE0",
  "#E6DBE8", "#DEE5F2", "#D0CFCF", "#A9BCD0", "#B4C4BA",
  "#D4DEEE", "#E9D9D8", "#DCE9E7", "#CBDCE5", "#EADFEA",
  "#E8E3D7", "#C5D6CF", "#D8DCE8", "#E5D5D7", "#D7E2E5"
)
# Optional named overrides, e.g. c("Oxidative stress"="#8293AF").
process_colors <- c()

# Font controls: face can be "plain", "bold", "italic" or "bold.italic".
font_family <- "sans"                     # portable Arial-like sans-serif; may also set "Arial"
show_row_names <- TRUE; row_font_size <- 16; row_font_face <- "bold"; row_font_color <- "#111111"
show_column_names <- FALSE; column_font_size <- 12; column_font_face <- "bold"; column_font_color <- "#111111"
group_font_size <- 22; group_font_face <- "bold"; group_font_color <- "#111111"
process_font_size <- 18; process_font_face <- "bold"; process_font_color <- "#111111"
legend_font_size <- 15; legend_font_face <- "bold"; legend_font_color <- "#111111"
# TRUE 显示热图颜色图例；FALSE 隐藏图例但不改变热图数据和配色。
show_heatmap_legend <- TRUE
legend_side <- "right"                   # 图外区域：left / right / top / bottom
legend_width_mm <- 4; legend_height_mm <- 32

# Annotation widths and label wrapping.
gene_name_width_cm <- 2.6; process_label_wrap <- 20; process_width_cm <- 7
column_name_rotation <- 45
image_width <- 12; image_height <- 15; dpi <- 600; output_formats <- c("png", "pdf")
# ============================ 用户配置区结束 ============================

setwd(work_dir); dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dat <- read.csv(expression_file, check.names = FALSE, stringsAsFactors = FALSE)
meta <- read.csv(metadata_file, check.names = FALSE, stringsAsFactors = FALSE)
need <- c("ComplexHeatmap", "circlize", "readxl")
miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) stop("缺少R包：", paste(miss, collapse = ", "))
if (!all(c(sample_id_col, group_col) %in% names(meta))) stop("group.csv缺少Sample或Group列。")
if (!all(c(gene_id_col, gene_label_col) %in% names(dat))) stop("表达表缺少基因ID或基因名列。")

meta <- meta[meta[[group_col]] %in% selected_groups, , drop = FALSE]
meta[[group_col]] <- factor(meta[[group_col]], levels = selected_groups)
meta <- meta[order(meta[[group_col]]), , drop = FALSE]; samples <- as.character(meta[[sample_id_col]])
if (!length(samples) || !all(samples %in% names(dat))) stop("筛选后无样本，或表达表缺少样本Count列。")
counts <- as.matrix(dat[, samples, drop = FALSE]); storage.mode(counts) <- "numeric"
rownames(counts) <- dat[[gene_id_col]]; keep <- rowSums(counts) >= min_total_count
counts <- counts[keep, , drop = FALSE]; d <- dat[keep, , drop = FALSE]

if (normalization_method == "vst") {
  if (!requireNamespace("DESeq2", quietly = TRUE)) stop("VST需要DESeq2。")
  dds <- DESeq2::DESeqDataSetFromMatrix(round(counts), data.frame(Group = meta[[group_col]], row.names = samples), ~Group)
  norm <- SummarizedExperiment::assay(DESeq2::varianceStabilizingTransformation(dds, blind = FALSE))
} else if (normalization_method == "log_cpm") {
  norm <- log2(sweep(counts, 2, colSums(counts) / 1e6, "/") + pseudo_count)
} else if (normalization_method == "log2") norm <- log2(counts + pseudo_count) else norm <- counts

truth <- function(x) tolower(as.character(x)) %in% c("true", "1", "yes", "y")
read_manual_now <- function() tryCatch(as.data.frame(readxl::read_excel(manual_annotation_file, sheet = "GeneAnnotation")), error = function(e) data.frame())
manual_early <- read_manual_now()
if (nrow(manual_early) && "Use" %in% names(manual_early)) manual_early <- manual_early[truth(manual_early$Use), , drop = FALSE]
if (nrow(manual_early) && !all(c("GeneKey", "Pathway") %in% names(manual_early))) stop("GeneAnnotation must contain GeneKey and Pathway.")
hit <- rep(TRUE, nrow(d))
if (filter_mode %in% c("top", "threshold")) hit <- !is.na(d[[padj_col]]) & d[[padj_col]] < padj_cutoff & abs(d[[log2fc_col]]) >= log2fc_cutoff
if (filter_mode == "custom") hit <- d[[gene_id_col]] %in% custom_genes | d[[gene_label_col]] %in% custom_genes
idx <- which(hit); rank_value <- d[[padj_col]]
if (filter_mode == "top") idx <- idx[order(rank_value[idx], na.last = TRUE)][seq_len(min(top_n_genes, length(idx)))]
if (length(idx) > max_genes) idx <- idx[order(rank_value[idx], na.last = TRUE)][seq_len(max_genes)]
if (include_all_annotated_genes && nrow(manual_early)) {
  manual_idx <- which(as.character(d[[gene_id_col]]) %in% manual_early$GeneKey |
                        as.character(d[[gene_label_col]]) %in% manual_early$GeneKey)
  idx <- if (include_unannotated_top_genes) unique(c(idx, manual_idx)) else manual_idx
}
if (length(idx) < 2) stop("少于2个基因通过筛选。")
selected <- d[idx, c(gene_id_col, gene_label_col, padj_col, log2fc_col), drop = FALSE]
norm_selected <- norm[idx, , drop = FALSE]; symbols <- as.character(selected[[gene_label_col]])

truth <- function(x) tolower(as.character(x)) %in% c("true", "1", "yes", "y")
read_sheet <- function(sheet) {
  if (!file.exists(manual_annotation_file)) return(data.frame())
  if (!requireNamespace("readxl", quietly = TRUE)) stop("读取Excel需要readxl包。")
  tryCatch(as.data.frame(readxl::read_excel(manual_annotation_file, sheet = sheet)), error = function(e) data.frame())
}
manual <- read_sheet("GeneAnnotation")
if (nrow(manual) && "Use" %in% names(manual)) manual <- manual[truth(manual$Use), , drop = FALSE]
targets <- data.frame() # 手工版不读取TargetPathways表

long <- data.frame()
add_terms <- function(res, db, id_to_symbol = NULL) {
  x <- as.data.frame(res); if (!nrow(x)) return(data.frame())
  z <- do.call(rbind, lapply(seq_len(nrow(x)), function(i) {
    genes <- strsplit(as.character(x$geneID[i]), "/", fixed = TRUE)[[1]]
    if (!is.null(id_to_symbol)) genes <- unname(id_to_symbol[genes])
    genes <- unique(genes[!is.na(genes) & genes != ""])
    data.frame(gene_name = genes, Pathway = x$Description[i], Database = db,
      PathwayID = x$ID[i], padj = x$p.adjust[i], Count = x$Count[i])
  })); z
}
if (auto_pathway_annotation) {
  orgdb <- get("org.Mm.eg.db", envir = asNamespace("org.Mm.eg.db"))
  if (use_go) {
    ego <- clusterProfiler::enrichGO(unique(symbols), OrgDb = orgdb, keyType = "SYMBOL", ont = "BP",
      universe = unique(as.character(d[[gene_label_col]])), pvalueCutoff = enrich_p_cutoff,
      qvalueCutoff = enrich_q_cutoff, minGSSize = min_pathway_genes, readable = FALSE)
    long <- rbind(long, add_terms(ego, "GO")); write.csv(as.data.frame(ego), file.path(output_dir, "GO_BP_enrichment.csv"), row.names = FALSE)
  }
  if (use_kegg) {
    conv <- clusterProfiler::bitr(unique(as.character(d[[gene_label_col]])), fromType = "SYMBOL", toType = "ENTREZID", OrgDb = orgdb)
    id_to_symbol <- setNames(conv$SYMBOL, conv$ENTREZID); selected_entrez <- conv$ENTREZID[conv$SYMBOL %in% symbols]
    ek <- tryCatch(clusterProfiler::enrichKEGG(unique(selected_entrez), organism = organism,
      universe = unique(conv$ENTREZID), pvalueCutoff = enrich_p_cutoff, qvalueCutoff = enrich_q_cutoff,
      minGSSize = min_pathway_genes), error = function(e) { warning("KEGG失败：", e$message); NULL })
    if (!is.null(ek)) { long <- rbind(long, add_terms(ek, "KEGG", id_to_symbol)); write.csv(as.data.frame(ek), file.path(output_dir, "KEGG_enrichment.csv"), row.names = FALSE) }
  }
}
if (nrow(long)) {
  key_hit <- grepl(paste(target_keywords, collapse = "|"), long$Pathway, ignore.case = TRUE)
  long$Score <- -log10(pmax(long$padj, 1e-300)) * log1p(long$Count) + keyword_score_bonus * key_hit
  long$TargetMatch <- FALSE
  if (nrow(targets)) for (i in seq_len(nrow(targets))) {
    id <- if ("PathwayID" %in% names(targets)) as.character(targets$PathwayID[i]) else ""
    nm <- if ("PathwayName" %in% names(targets)) as.character(targets$PathwayName[i]) else ""
    db <- if ("Database" %in% names(targets)) as.character(targets$Database[i]) else ""
    m <- (nzchar(id) & long$PathwayID == id) | (nzchar(nm) & grepl(nm, long$Pathway, ignore.case = TRUE))
    if (nzchar(db)) m <- m & toupper(long$Database) == toupper(db)
    priority <- if ("Priority" %in% names(targets) && is.finite(as.numeric(targets$Priority[i]))) as.numeric(targets$Priority[i]) else 1
    long$TargetMatch[m] <- TRUE; long$Score[m] <- long$Score[m] + target_excel_bonus * priority
  }
  if (target_pathways_only && nrow(targets)) long <- long[long$TargetMatch, , drop = FALSE]
  long <- long[order(-long$Score, long$padj), , drop = FALSE]
}
assignment <- data.frame(gene_id = selected[[gene_id_col]], gene_name = symbols,
  Pathway = unassigned_process, Database = "Unassigned", PathwayID = NA, padj = NA, Score = NA, Source = "Unassigned")
if (nrow(long)) for (i in seq_len(nrow(assignment))) {
  a <- long[long$gene_name == assignment$gene_name[i], , drop = FALSE]
  if (nrow(a)) assignment[i, c("Pathway", "Database", "PathwayID", "padj", "Score", "Source")] <- c(a$Pathway[1], a$Database[1], a$PathwayID[1], a$padj[1], a$Score[1], "Auto")
}
assignment$AutoPathway <- assignment$Pathway; assignment$AutoDatabase <- assignment$Database
assignment$AutoPadj <- assignment$padj; assignment$AutoScore <- assignment$Score
source_row <- seq_len(nrow(assignment))
if (nrow(manual) && all(c("GeneKey", "Pathway") %in% names(manual))) {
  expanded <- lapply(seq_len(nrow(assignment)), function(i) {
    a <- manual[manual$GeneKey %in% c(assignment$gene_name[i], assignment$gene_id[i]), , drop = FALSE]
    a <- a[!is.na(a$Pathway) & nzchar(trimws(as.character(a$Pathway))), , drop = FALSE]
    if (exclude_manual_other && any(tolower(a$Pathway) != "other")) a <- a[tolower(a$Pathway) != "other", , drop = FALSE]
    if (!nrow(a)) return(cbind(assignment[i, , drop = FALSE], SourceRow = i))
    if (!show_all_gene_pathways) a <- a[1, , drop = FALSE]
    out <- assignment[rep(i, nrow(a)), , drop = FALSE]
    out$Pathway <- as.character(a$Pathway)
    out$Database <- if ("Database" %in% names(a)) as.character(a$Database) else "Manual"
    out$PathwayID <- if ("PathwayID" %in% names(a)) as.character(a$PathwayID) else NA
    out$Source <- "Manual"; out$padj <- NA_real_; out$Score <- NA_real_
    cbind(out, SourceRow = i)
  })
  assignment <- do.call(rbind, expanded); rownames(assignment) <- NULL
  source_row <- assignment$SourceRow; assignment$SourceRow <- NULL
  norm_selected <- norm_selected[source_row, , drop = FALSE]
  symbols <- assignment$gene_name
}
write.csv(long, file.path(output_dir, "Auto_pathway_gene_candidates.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(assignment, file.path(output_dir, "Final_gene_pathway_assignment.csv"), row.names = FALSE, fileEncoding = "UTF-8")

scale_safe <- function(x) { z <- t(scale(t(x))); z[!is.finite(z)] <- 0; z }
plot_mat <- if (heatmap_scale == "row") scale_safe(norm_selected) else norm_selected
rownames(plot_mat) <- make.unique(symbols)
process <- assignment$Pathway; present <- unique(process)
treat_cols <- which(meta[[group_col]] == selected_groups[2]); control_cols <- which(meta[[group_col]] == selected_groups[1])
gene_delta <- rowMeans(plot_mat[, treat_cols, drop = FALSE]) - rowMeans(plot_mat[, control_cols, drop = FALSE])
pathway_delta <- tapply(gene_delta, process, mean, na.rm = TRUE)
if (!is.null(process_order)) {
  process_levels <- c(intersect(process_order, present), setdiff(present, process_order))
} else if (order_pathways_by_direction) {
  process_levels <- names(sort(pathway_delta[present], decreasing = TRUE))
} else process_levels <- present
process_factor <- factor(process, levels = process_levels)

# Use group means for ordering only; the heatmap itself still shows every sample.
ordering_mat <- if (cluster_on_group_means) {
  sapply(selected_groups, function(g) rowMeans(plot_mat[, meta[[group_col]] == g, drop = FALSE]))
} else plot_mat

# First separate expression directions inside each pathway, then cluster within each direction.
safe_row_distance <- function(m, method) {
  if (nrow(m) < 2) return(NULL)
  if (method %in% c("pearson", "spearman")) {
    r <- suppressWarnings(cor(t(m), method = method, use = "pairwise.complete.obs"))
    dm <- 1 - r; dm[!is.finite(dm) | dm < 0] <- 0; diag(dm) <- 0
    return(as.dist(dm))
  }
  dist(m, method = method)
}
active_distance <- if (cluster_on_group_means) group_mean_distance else distance_rows
gene_direction <- ifelse(gene_delta >= gene_direction_cutoff, 1L,
  ifelse(gene_delta <= -gene_direction_cutoff, -1L, 0L))
order_one_set <- function(ii) {
  if (!cluster_within_process || length(ii) < 2) return(ii[order(gene_delta[ii], decreasing = TRUE)])
  hc <- hclust(safe_row_distance(ordering_mat[ii, , drop = FALSE], active_distance), method = clustering_method)
  ii[order.dendrogram(reorder(as.dendrogram(hc), wts = gene_delta[ii], agglo.FUN = mean))]
}
ordered_rows <- unlist(lapply(process_levels, function(p) {
  ii <- which(process == p)
  if (!order_genes_by_direction) return(order_one_set(ii))
  unlist(lapply(c(1L, 0L, -1L), function(z) order_one_set(ii[gene_direction[ii] == z])), use.names = FALSE)
}), use.names = FALSE)
plot_mat <- plot_mat[ordered_rows, , drop = FALSE]
assignment <- assignment[ordered_rows, , drop = FALSE]; symbols <- symbols[ordered_rows]
gene_delta <- gene_delta[ordered_rows]; gene_direction <- gene_direction[ordered_rows]; process <- process[ordered_rows]
process_factor <- factor(process, levels = process_levels)
assignment$GeneDelta <- gene_delta
assignment$PathwayDelta <- unname(pathway_delta[process])
assignment$GeneRegulation <- ifelse(gene_direction > 0, paste0(selected_groups[2], " higher"),
  ifelse(gene_direction < 0, paste0(selected_groups[1], " higher"), "Mixed"))
assignment$RegulationPattern <- ifelse(assignment$PathwayDelta >= pathway_direction_cutoff,
  paste0(selected_groups[2], " higher"), ifelse(assignment$PathwayDelta <= -pathway_direction_cutoff,
  paste0(selected_groups[1], " higher"), "Mixed"))
write.csv(assignment, file.path(output_dir, "Final_gene_pathway_assignment.csv"), row.names = FALSE, fileEncoding = "UTF-8")
auto_process_colors <- setNames(rep(morandi_process_palette,
  length.out = length(process_levels)), process_levels)
if (length(process_colors)) {
  valid_overrides <- intersect(names(process_colors), process_levels)
  auto_process_colors[valid_overrides] <- process_colors[valid_overrides]
}
process_colors <- auto_process_colors
col_fun <- circlize::colorRamp2(c(-scale_limit, 0, scale_limit), heatmap_colors)
labels <- setNames(vapply(process_levels, function(x) paste(strwrap(x, process_label_wrap), collapse = "\n"), character(1)), process_levels)
gene_fun <- ComplexHeatmap::AnnotationFunction(which = "row", width = grid::unit(gene_name_width_cm, "cm"), fun = function(index, k, n) {
  nr <- length(index); y <- grid::unit((rev(seq_len(nr)) - .5) / nr, "npc")
  grid::grid.rect(.5, y, grid::unit(1, "npc"), grid::unit(1 / nr, "npc"), gp = grid::gpar(fill = process_colors[as.character(process_factor[index])], col = NA))
  if (show_row_names) grid::grid.text(symbols[index], .5, y,
    gp = grid::gpar(fontfamily = font_family, fontsize = row_font_size,
      fontface = row_font_face, col = row_font_color))
})
block_fun <- function(index, levels) grid::grid.text(labels[as.character(levels[1])],
  gp = grid::gpar(fontfamily = font_family, fontsize = process_font_size,
    fontface = process_font_face, col = process_font_color))
ra <- ComplexHeatmap::rowAnnotation(Gene = gene_fun, Process = ComplexHeatmap::anno_block(panel_fun = block_fun, width = grid::unit(process_width_cm, "cm")), show_annotation_name = FALSE, gap = grid::unit(annotation_gap_mm, "mm"))
col_dist <- if (distance_columns %in% c("pearson", "spearman")) function(m) as.dist(1 - cor(t(m), method = distance_columns)) else distance_columns
ht <- ComplexHeatmap::Heatmap(plot_mat, name = "Relative expression", col = col_fun, na_col = na_color,
  row_split = process_factor, cluster_rows = FALSE, cluster_row_slices = FALSE, show_row_dend = FALSE,
  column_split = meta[[group_col]], column_title = levels(meta[[group_col]]), cluster_columns = cluster_columns,
  cluster_column_slices = FALSE, show_column_dend = show_column_dendrogram, clustering_distance_columns = col_dist,
  clustering_method_columns = clustering_method, top_annotation = NULL, right_annotation = ra,
  row_gap = grid::unit(row_gap_mm, "mm"), column_gap = grid::unit(column_gap_mm, "mm"), row_title = NULL, show_row_names = FALSE,
  show_column_names = show_column_names, column_names_rot = column_name_rotation,
  column_names_gp = grid::gpar(fontfamily = font_family, fontsize = column_font_size,
    fontface = column_font_face, col = column_font_color),
  column_title_gp = grid::gpar(fontfamily = font_family, fontsize = group_font_size,
    fontface = group_font_face, col = group_font_color),
  heatmap_legend_param = list(title = "", direction = if (legend_side %in% c("top", "bottom")) "horizontal" else "vertical",
    labels_gp = grid::gpar(fontfamily = font_family, fontsize = legend_font_size,
      fontface = legend_font_face, col = legend_font_color),
    grid_width = grid::unit(legend_width_mm, "mm"), grid_height = grid::unit(legend_width_mm, "mm"),
    legend_height = grid::unit(legend_height_mm, "mm"), legend_width = grid::unit(legend_height_mm, "mm")),
  show_heatmap_legend = show_heatmap_legend,
  rect_gp = grid::gpar(col = cell_border_color, lwd = cell_border_width),
  use_raster = use_raster_heatmap)
draw_file <- function(fmt) {
  path <- file.path(output_dir, paste0(project_name, "_Heatmap.", fmt))
  if (fmt == "pdf") pdf(path, image_width, image_height) else png(path, image_width, image_height, units = "in", res = dpi)
  out <- ComplexHeatmap::draw(ht, heatmap_legend_side = legend_side,
    align_heatmap_legend = "global_center"); dev.off(); out
}
drawn <- NULL; for (fmt in output_formats) { z <- draw_file(fmt); if (is.null(drawn)) drawn <- z }
ro <- unlist(ComplexHeatmap::row_order(drawn), use.names = FALSE); co <- unlist(ComplexHeatmap::column_order(drawn), use.names = FALSE)
plot_data <- data.frame(assignment[ro, ], plot_mat[ro, co, drop = FALSE], check.names = FALSE)
write.csv(plot_data, file.path(output_dir, paste0(project_name, "_PlotData.csv")), row.names = FALSE, fileEncoding = "UTF-8")
message("完成：", nrow(plot_mat), "个基因；GO候选=", sum(long$Database == "GO"), "，KEGG候选=", sum(long$Database == "KEGG"),
  "；手工注释=", sum(assignment$Source == "Manual"), "；自动注释=", sum(assignment$Source == "Auto"), "。")
