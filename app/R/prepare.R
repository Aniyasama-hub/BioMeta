# 数据准备层：参数变更在此触发筛选/PCA/聚类，绘图层只消费结果。
choose_expression <- function(analysis, selection) {
  if (!selection$use_batch_visualization) return(analysis$vst)
  if (is.null(analysis$vst_batch)) stop("尚未生成去批次展示矩阵；请先启用并运行分析。")
  analysis$vst_batch
}

compute_distance <- function(matrix, method) {
  if (method == "euclidean") return(stats::dist(matrix))
  if (method != "pearson") stop("distance只支持pearson/euclidean。")
  correlation <- stats::cor(t(matrix), method = "pearson")
  if (any(!is.finite(correlation))) stop("相关距离遇到常数向量，请换欧氏距离。")
  stats::as.dist(pmax(1 - correlation, 0))
}

prepare_heatmap <- function(analysis, selection) {
  expression <- choose_expression(analysis, selection)
  match_report <- data.frame()
  if (selection$heatmap_mode == "custom") {
    targets <- read_table(selection$target_genes)
    if (!"GeneKey" %in% names(targets)) stop("目标基因表缺少GeneKey。")
    if ("Use" %in% names(targets)) {
      if (any(!toupper(targets$Use) %in% c("TRUE", "FALSE", ""))) stop("Use只能TRUE/FALSE/空。")
      targets <- targets[toupper(targets$Use) != "FALSE", , drop = FALSE]
    }
    targets$GeneKey <- trimws(targets$GeneKey)
    matches <- lapply(seq_len(nrow(targets)), function(i) {
      key <- targets$GeneKey[i]
      ids <- analysis$genes$gene_id[analysis$genes$gene_id == key |
                                    (!is.na(analysis$genes$gene_name) & analysis$genes$gene_name == key)]
      data.frame(GeneKey = key, gene_id = if (length(ids)) ids else NA_character_,
                  status = if (!length(ids)) "unmatched" else ifelse(ids %in% rownames(expression),
                                                                          "matched", "filtered_from_model"),
                  stringsAsFactors = FALSE)
    })
    if (!length(matches)) stop("目标基因列表为空。")
    match_report <- do.call(rbind, matches)
    ids <- unique(match_report$gene_id[match_report$status == "matched"])
    # 不把同名稳定ID自动相加；多重命中明确保留在匹配报告。
  } else if (selection$heatmap_mode == "deg") {
    selected <- analysis$deg[selection_mask(analysis$deg, selection), , drop = FALSE]
    selected <- selected[order(selected$padj, -abs(selected[[selection$lfc_column]]),
                                selected$gene_id), , drop = FALSE]
    ids <- head(selected$gene_id, selection$heatmap_top_n)
  } else if (selection$heatmap_mode == "variable") {
    variances <- apply(expression, 1, stats::var)
    ids <- head(names(sort(variances, decreasing = TRUE)), selection$heatmap_top_n)
  } else stop("heatmap_mode须为deg/variable/custom。")
  matrix <- expression[intersect(ids, rownames(expression)), , drop = FALSE]
  if (!nrow(matrix)) stop("没有可绘制基因；完整分析已保留，请检查筛选或基因匹配报告。")
  constant <- apply(matrix, 1, stats::sd) == 0
  excluded <- data.frame(gene_id = rownames(matrix)[constant], reason = rep("zero_variance", sum(constant)))
  matrix <- matrix[!constant, , drop = FALSE]
  if (!nrow(matrix)) stop("所选基因全部无样本间变异。")
  before_scale <- matrix
  if (selection$row_zscore) matrix <- t(scale(t(matrix)))
  # 保存未截断Z-score；颜色范围只由style控制，避免永久丢失极值。
  row_tree <- column_tree <- NULL
  if (selection$linkage == "ward.D2" && selection$distance != "euclidean") {
    stop("ward.D2须搭配euclidean距离。")
  }
  if (selection$cluster_rows && nrow(matrix) > 1) {
    row_tree <- stats::hclust(compute_distance(matrix, selection$distance), method = selection$linkage)
  }
  if (selection$cluster_columns && ncol(matrix) > 1) {
    column_tree <- stats::hclust(compute_distance(t(matrix), selection$distance), method = selection$linkage)
  }
  row_order <- if (is.null(row_tree)) seq_len(nrow(matrix)) else row_tree$order
  column_order <- if (is.null(column_tree)) seq_len(ncol(matrix)) else column_tree$order
  sample_annotation <- analysis$samples[colnames(matrix), c("condition", "batch"), drop = FALSE]
  row_labels <- analysis$genes[rownames(matrix), "gene_name"]
  row_labels[is.na(row_labels) | row_labels == ""] <- rownames(matrix)[is.na(row_labels) | row_labels == ""]
  row_annotation <- NULL
  if (selection$heatmap_mode == "custom" && "Pathway" %in% names(targets)) {
    pathway <- targets$Pathway[match(rownames(matrix), targets$GeneKey)]
    missing <- is.na(pathway)
    pathway[missing] <- targets$Pathway[match(row_labels[missing], targets$GeneKey)]
    row_annotation <- data.frame(Pathway = ifelse(is.na(pathway), "Unassigned", pathway))
  }
  list(type = "heatmap", data = matrix,
       extras = list(matrix_units = if (selection$row_zscore) "row_zscore" else "VST",
                     expression_before_scale = before_scale, row_order = row_order,
                     column_order = column_order, row_tree = row_tree, column_tree = column_tree,
                     row_labels = row_labels, row_annotation = row_annotation,
                     sample_annotation = sample_annotation, gene_match_report = match_report,
                     excluded_genes = excluded))
}

prepare_bundle <- function(analysis, cfg, type, pathways = NULL) {
  selection <- cfg$selection
  if (type == "pca") {
    expression <- choose_expression(analysis, selection)
    variances <- apply(expression, 1, stats::var)
    ids <- head(names(sort(variances[variances > 0], decreasing = TRUE)), selection$pca_top_genes)
    if (length(ids) < 2) stop("PCA至少需要两个非恒定基因。")
    pca <- stats::prcomp(t(expression[ids, , drop = FALSE]),
                         center = TRUE, scale. = selection$pca_scale)
    variance <- pca$sdev^2 / sum(pca$sdev^2) * 100
    data <- data.frame(sample_id = rownames(pca$x),
                       condition = analysis$samples[rownames(pca$x), "condition"],
                       pca$x, check.names = FALSE)
    return(list(type = "pca", data = data,
                 extras = list(variance = variance, genes = ids, pca = pca,
                               batch_removed = selection$use_batch_visualization)))
  }
  if (type == "volcano") {
    data <- analysis$deg
    data$log2FoldChange <- data[[selection$lfc_column]]
    hit <- selection_mask(analysis$deg, selection)
    data$regulation <- ifelse(hit & data$log2FoldChange > 0, "Up",
                               ifelse(hit & data$log2FoldChange < 0, "Down", "Not_significant"))
    data$minus_log10_padj <- -log10(pmax(data$padj, 1e-300))
    data$label <- FALSE
    for (direction in c("Up", "Down")) {
      indices <- which(data$regulation == direction & is.finite(data$padj))
      indices <- head(indices[order(data$padj[indices], data$gene_id[indices])], selection$label_top_n)
      data$label[indices] <- TRUE
    }
    data$plottable <- is.finite(data$log2FoldChange) & is.finite(data$minus_log10_padj)
    return(list(type = "volcano", data = data,
                 extras = list(padj_cutoff = selection$padj_cutoff,
                               log2fc_cutoff = selection$log2fc_cutoff,
                               lfc_column = selection$lfc_column,
                               category_summary = as.data.frame(table(data$regulation)))))
  }
  if (type == "heatmap") return(prepare_heatmap(analysis, selection))
  if (is.null(pathways)) stop("此图型需要先执行pathways阶段并启用对应模块。")
  if (type == "enrichment") {
    table <- pathways$ora$results
    if (is.null(table)) stop("未运行ORA模块。")
    table <- table[is.finite(table$p.adjust) & table$p.adjust < cfg$pathways$ora_padj, , drop = FALSE]
    table <- head(table[order(table$p.adjust, -table$Count), , drop = FALSE], selection$pathway_top_n)
    if (!nrow(table)) stop("没有符合阈值的富集条目；完整富集结果仍已保存。")
    ratio <- vapply(strsplit(table$GeneRatio, "/", fixed = TRUE),
                     function(x) as.numeric(x[1]) / as.numeric(x[2]), numeric(1))
    return(list(type = "enrichment",
                 data = data.frame(term_id = table$ID, description = table$Description,
                                    padj = table$p.adjust, gene_ratio = ratio, count = table$Count,
                                    source = cfg$pathways$database_label), extras = list()))
  }
  if (type == "gsea") {
    table <- pathways$gsea$results
    if (is.null(table) || !nrow(table)) stop("GSEA无可展示结果。")
    id <- selection$pathway_id %||% table$pathway[order(table$padj, -abs(table$NES))][1]
    row <- table[table$pathway == id, , drop = FALSE]
    if (nrow(row) != 1) stop("pathway_id未唯一匹配GSEA结果。")
    stats <- pathways$gsea$ranked_stats
    hit <- names(stats) %in% pathways$gsea$pathways[[id]]
    weights <- abs(stats)
    total <- sum(weights[hit])
    if (!any(hit) || all(hit) || total == 0) stop("该基因集无法构建有效运行曲线。")
    running <- cumsum(ifelse(hit, weights / total, -1 / sum(!hit)))
    data <- data.frame(rank = seq_along(stats), gene = names(stats),
                       running_es = running, hit = hit, rank_score = unname(stats))
    return(list(type = "gsea", data = data,
                 extras = list(pathway_id = id, nes = row$NES, padj = row$padj,
                               weighting_exponent = 1)))
  }
  if (type == "network") {
    if (is.null(pathways$ppi) || !nrow(pathways$ppi$nodes)) stop("PPI无可展示节点。")
    return(list(type = "network", data = pathways$ppi$nodes,
                 extras = list(edges = pathways$ppi$edges)))
  }
  if (type == "gsva") {
    table <- pathways$gsva$results
    if (is.null(table) || !nrow(table)) stop("GSVA无可展示结果。")
    ids <- head(table$term_id[order(table$adj.P.Val, -abs(table$logFC))], selection$pathway_top_n)
    matrix <- pathways$gsva$scores[ids, , drop = FALSE]
    constant <- apply(matrix, 1, stats::sd) == 0
    matrix <- matrix[!constant, , drop = FALSE]
    if (!nrow(matrix)) stop("GSVA所选通路全部恒定。")
    unscaled <- matrix
    if (selection$row_zscore) matrix <- t(scale(t(matrix)))
    return(list(type = "heatmap", data = matrix,
                 extras = list(matrix_units = if (selection$row_zscore) "row_zscore" else "GSVA_score",
                               expression_before_scale = unscaled, row_labels = rownames(matrix),
                               row_order = seq_len(nrow(matrix)), column_order = seq_len(ncol(matrix)),
                               sample_annotation = analysis$samples[colnames(matrix), c("condition", "batch")],
                               statistics = table)))
  }
  stop("未知图型：", type)
}

export_bundle <- function(bundle, directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  saveRDS(bundle, file.path(directory, "bundle.rds"))
  if (is.matrix(bundle$data)) {
    rows <- bundle$extras$row_order
    columns <- bundle$extras$column_order
    matrix <- bundle$data[rows, columns, drop = FALSE]
    write_table(data.frame(gene_id = rownames(matrix), matrix, check.names = FALSE),
                file.path(directory, "plot_data.csv"))
    write_table(data.frame(gene_id = rownames(bundle$data)[rows],
                           label = bundle$extras$row_labels[rows]),
                file.path(directory, "row_order.csv"))
    write_table(data.frame(sample_id = colnames(bundle$data)[columns]),
                file.path(directory, "column_order.csv"))
  } else write_table(bundle$data, file.path(directory, "plot_data.csv"))
  for (name in names(bundle$extras)) {
    value <- bundle$extras[[name]]
    if (is.data.frame(value)) write_table(value, file.path(directory, paste0(name, ".csv")))
  }
  if (bundle$type == "pca") {
    write_table(data.frame(PC = paste0("PC", seq_along(bundle$extras$variance)),
                           variance_percent = bundle$extras$variance),
                file.path(directory, "variance.csv"))
    loadings <- bundle$extras$pca$rotation
    write_table(data.frame(gene_id = rownames(loadings), loadings),
                file.path(directory, "gene_loadings.csv"))
  }
  before <- bundle$extras$expression_before_scale
  if (!is.null(before)) write_table(data.frame(gene_id = rownames(before), before, check.names = FALSE),
                                    file.path(directory, "expression_before_scale.csv"))
}
