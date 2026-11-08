# 数据准备层：参数变更在此触发筛选/PCA/聚类，绘图层只消费结果。
choose_expression <- function(analysis, selection) {
  if (!selection$use_batch_visualization) return(analysis$vst)
  if (is.null(analysis$vst_batch)) stop("尚未生成去批次展示矩阵；请先启用并运行分析。")
  analysis$vst_batch
}

compute_distance <- function(matrix, method) {
  if (method %in% c("euclidean", "manhattan")) return(stats::dist(matrix, method = method))
  if (!method %in% c("pearson", "spearman")) stop("不支持的聚类距离。")
  correlation <- stats::cor(t(matrix), method = method)
  if (any(!is.finite(correlation))) stop("相关距离遇到常数向量，请换欧氏距离。")
  stats::as.dist(pmax(1 - correlation, 0))
}

heatmap_bad_gene <- function(x) {
  x <- trimws(as.character(x))
  date <- grepl("^(?:[0-9]{1,4}[-/.][0-9]{1,2}[-/.][0-9]{1,4}|[0-9]{1,2}[-/](?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-/][0-9]{1,2})(?:$|[ T])",
    x, ignore.case = TRUE, perl = TRUE)
  opaque <- grepl("^[0-9]{13,}$|^[[:xdigit:]]{24,}$|^[A-Za-z0-9]{48,}$|^[0-9]+([.][0-9]+)?[Ee][+-][0-9]+$|^https?://", x, ignore.case = TRUE)
  invalid <- !grepl("^[A-Za-z0-9][A-Za-z0-9_.:+/*-]{0,63}$", x)
  !is.na(x) & nzchar(x) & (date | opaque | invalid)
}

heatmap_gene_exclusions <- function(ids, labels) {
  bad <- heatmap_bad_gene(ids) | heatmap_bad_gene(labels)
  data.frame(gene_id = ids[bad], gene_name = labels[bad], reason = rep("invalid_gene_annotation", sum(bad)))
}

heatmap_column_plan <- function(matrix, samples, selection) {
  groups <- samples$condition
  if (!is.null(groups) && (anyNA(groups) || any(!nzchar(trimws(as.character(groups)))))) stop("热图样本分组不能为空。")
  if (is.null(groups) || identical(selection$column_cluster_mode, "global")) {
    blocks <- list(seq_len(ncol(matrix)))
  } else {
    levels <- if (is.factor(groups)) levels(droplevels(groups)) else unique(groups)
    blocks <- split(seq_len(ncol(matrix)), factor(groups, levels = levels))
  }
  order <- function(ids) {
    if (!isTRUE(selection$cluster_columns) || length(ids) < 2L) return(ids)
    tree <- stats::hclust(compute_distance(t(matrix[, ids, drop = FALSE]), selection$distance),
      method = selection$linkage)
    ids[tree$order]
  }
  unlist(lapply(blocks, order), use.names = FALSE)
}


prepare_heatmap <- function(analysis, selection) {
  expression <- choose_expression(analysis, selection)
  genes <- analysis$genes
  excluded <- if (!identical(selection$sanitize_genes, FALSE)) heatmap_gene_exclusions(genes$gene_id, genes$gene_name)
    else heatmap_gene_exclusions(character(), character())
  expression <- expression[!rownames(expression) %in% excluded$gene_id, , drop = FALSE]
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
    selected <- selected[selected$gene_id %in% rownames(expression), , drop = FALSE]
    selected <- selected[order(selected$padj, -abs(selected[[selection$lfc_column]]),
                                selected$gene_id), , drop = FALSE]
    ids <- head(selected$gene_id, selection$heatmap_top_n)
  } else if (selection$heatmap_mode == "variable") {
    if (!nrow(expression)) stop("剔除异常基因注释后没有可绘制的基因。")
    variances <- apply(expression, 1, stats::var)
    ids <- head(names(sort(variances, decreasing = TRUE)), selection$heatmap_top_n)
  } else stop("heatmap_mode须为deg/variable/custom。")
  matrix <- expression[intersect(ids, rownames(expression)), , drop = FALSE]
  if (!nrow(matrix)) stop("没有可绘制基因；完整分析已保留，请检查筛选或基因匹配报告。")
  constant <- apply(matrix, 1, stats::sd) == 0
  excluded <- rbind(excluded, data.frame(gene_id = rownames(matrix)[constant],
    gene_name = genes$gene_name[match(rownames(matrix)[constant], genes$gene_id)], reason = rep("zero_variance", sum(constant))))
  matrix <- matrix[!constant, , drop = FALSE]
  if (!nrow(matrix)) stop("所选基因全部无样本间变异。")
  before_scale <- matrix
  if (selection$row_zscore) matrix <- t(scale(t(matrix)))
  # 保存未截断Z-score；颜色范围只由style控制，避免永久丢失极值。
  row_tree <- NULL
  if (selection$linkage == "ward.D2" && selection$distance != "euclidean") {
    stop("ward.D2须搭配euclidean距离。")
  }
  if (selection$cluster_rows && nrow(matrix) > 1) {
    row_tree <- stats::hclust(compute_distance(matrix, selection$distance), method = selection$linkage)
  }
  row_order <- if (is.null(row_tree)) seq_len(nrow(matrix)) else row_tree$order
  sample_annotation <- analysis$samples[colnames(matrix), c("condition", "batch"), drop = FALSE]
  column_order <- heatmap_column_plan(matrix, sample_annotation, selection)
  row_labels <- as.character(genes$gene_name[match(rownames(matrix), genes$gene_id)])
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
                     column_order = column_order, row_tree = row_tree,
                     clustering = selection[c("cluster_rows", "cluster_columns", "distance", "linkage", "column_cluster_mode")],
                     row_labels = row_labels, row_annotation = row_annotation,
                     sample_annotation = sample_annotation, gene_match_report = match_report,
                     excluded_genes = excluded))
}

prepare_bundle <- function(analysis, cfg, type, pathways = NULL) {
  selection <- cfg$selection
  if (type == "pca") {
    expression <- choose_expression(analysis, selection)
    if (!nrow(expression)) stop("剔除异常基因注释后没有可绘制的基因。")
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
    filter_metric <- tb_pathway_metric(table, cfg$pathways$ora_metric %||% "padj")
    table <- table[is.finite(filter_metric) & filter_metric <= cfg$pathways$ora_padj, , drop = FALSE]
    terms <- selection$pathway_terms
    if (length(terms)) table <- table[table$ID %in% terms | table$Description %in% terms, , drop = FALSE]
    if (!nrow(table)) stop("没有符合阈值的富集条目；完整富集结果仍已保存。")
    ratio <- vapply(strsplit(table$GeneRatio, "/", fixed = TRUE),
      function(x) as.numeric(x[1]) / as.numeric(x[2]), numeric(1))
    data <- data.frame(term_id = table$ID, description = table$Description,
      pvalue = table$pvalue, padj = table$p.adjust, FDR = table$p.adjust,
      gene_ratio = ratio, count = table$Count, source = cfg$pathways$database_label)
    data$target_pathway <- table$target_pathway %||% rep(FALSE, nrow(table))
    if ("ontology" %in% names(table)) data$ontology <- table$ontology
    metric <- selection$gsea_sort %||% "padj"
    rank <- tb_pathway_metric(data, metric)
    if ((selection$gsea_order %||% "asc") == "desc") rank <- -rank
    data <- data[order(rank, -data$gene_ratio, data$term_id, na.last = NA), , drop = FALSE]
    make <- function(rows) list(type = "enrichment", data = rows, extras = list(sort_metric = metric))
    if (!nrow(data)) stop("所选通路排序指标没有有限数值。")
    if ("ontology" %in% names(data)) {
      categories <- c("BP", "CC", "MF")
      parts <- lapply(categories, function(category) head(data[data$ontology == category, , drop = FALSE], selection$pathway_top_n))
      names(parts) <- paste0("go_", categories)
      combined <- do.call(rbind, parts)
      scope <- selection$go_output_scope %||% "both"
      plots <- list()
      if (scope %in% c("both", "combined")) {
        plots$go_BP_CC_MF <- make(combined)
        plots$go_BP_CC_MF$extras$go_facets <- TRUE
      }
      if (scope %in% c("both", "single")) for (key in names(parts))
        if (nrow(parts[[key]])) plots[[key]] <- make(parts[[key]])
      requested <- categories %in% (selection$go_ontology %||% categories)
      return(list(type = "enrichment_collection", plots = plots,
        index = data.frame(ontology = categories, requested = requested,
          displayed = vapply(parts, nrow, integer(1)),
          note = ifelse(!requested, "未选择此分类（未检验）",
            ifelse(vapply(parts, nrow, integer(1)) > 0, "", "无符合当前阈值的条目")))))
    }
    return(make(head(data, selection$pathway_top_n)))
  }
  if (type == "gsea") {
    result <- pathways$gsea
    table <- result$results
    if (is.null(table) || !nrow(table)) stop("所选数据库没有可展示的 GSEA 通路。")
    table <- table[.gsea_order(table, selection), , drop = FALSE]
    if (!is.null(selection$pathway_id)) {
      table <- table[table$pathway == selection$pathway_id, , drop = FALSE]
      if (!nrow(table)) stop("指定通路 ID 未匹配所选数据库的 GSEA 结果。")
    }
    table <- head(table[is.finite(tb_pathway_metric(table, selection$gsea_sort %||% "padj")) & is.finite(table$NES), , drop = FALSE], selection$pathway_top_n)
    if (!nrow(table)) stop("没有可按所选指标排序的通路。")
    stats <- result$ranked_stats
    weights <- abs(stats)
    index <- data.frame(folder = sprintf("gsea-%03d", seq_len(nrow(table))),
      pathway_id = table$pathway, pathway_name = table$description %||% table$pathway,
      NES = table$NES, pvalue = table$pval, FDR = table$padj,
      database = cfg$pathways$database_label)
    curves <- lapply(seq_len(nrow(index)), function(i) {
      id <- index$pathway_id[i]
      hit <- names(stats) %in% result$pathways[[id]]
      if (!any(hit) || all(hit)) stop("基因集无法构建有效运行曲线：", id)
      total <- sum(weights[hit])
      increments <- if (total > 0) weights / total else rep(1 / sum(hit), length(hit))
      data <- data.frame(rank = seq_along(stats), gene = names(stats),
        running_es = cumsum(ifelse(hit, increments, -1 / sum(!hit))), hit = hit, rank_score = unname(stats))
      list(type = "gsea", data = data, extras = list(pathway_id = id, pathway_name = index$pathway_name[i],
        database = index$database[i], nes = index$NES[i], padj = index$FDR[i], pvalue = index$pvalue[i],
        weighting_exponent = 1))
    })
    return(list(type = "gsea_collection", curves = stats::setNames(curves, index$folder), index = index))
  }

  if (type == "network") {
    if (is.null(pathways$ppi) || !nrow(pathways$ppi$nodes)) stop("PPI无可展示节点。")
    return(list(type = "network", data = pathways$ppi$nodes,
                 extras = list(edges = pathways$ppi$edges)))
  }
  if (type == "gsva") {
    table <- pathways$gsva$results
    if (is.null(table) || !nrow(table)) stop("GSVA无可展示结果。")
    terms <- selection$pathway_terms
    if (length(terms)) table <- table[table$term_id %in% terms, , drop = FALSE]
    if (!nrow(table)) stop("指定的 GSVA 条目未匹配结果，请核对注释来源、条目 ID 与基因集大小。")
    metric <- tb_pathway_metric(table, selection$gsea_sort %||% "padj")
    if ((selection$gsea_order %||% "asc") == "desc") metric <- -metric
    ids <- head(table$term_id[order(metric, -abs(table$logFC), na.last = NA)], selection$pathway_top_n)
    matrix <- pathways$gsva$scores[ids, , drop = FALSE]
    constant <- apply(matrix, 1, stats::sd) == 0
    matrix <- matrix[!constant, , drop = FALSE]
    if (!nrow(matrix)) stop("GSVA所选通路全部恒定。")
    unscaled <- matrix
    if (selection$row_zscore) matrix <- t(scale(t(matrix)))
    annotation <- analysis$samples[colnames(matrix), c("condition", "batch"), drop = FALSE]
    row_order <- if (isTRUE(selection$cluster_rows) && nrow(matrix) > 1L)
      stats::hclust(compute_distance(matrix, selection$distance), method = selection$linkage)$order else seq_len(nrow(matrix))
    return(list(type = "heatmap", data = matrix,
                 extras = list(matrix_units = if (selection$row_zscore) "row_zscore" else "GSVA_score",
                               row_targets = (table$target_pathway %||% rep(FALSE, nrow(table)))[match(rownames(matrix), table$term_id)],
                               expression_before_scale = unscaled, row_labels = rownames(matrix),
                               row_order = row_order, column_order = heatmap_column_plan(matrix, annotation, selection),
                               clustering = selection[c("cluster_rows", "cluster_columns", "distance", "linkage", "column_cluster_mode")],
                               sample_annotation = annotation,
                               statistics = table)))
  }
  stop("未知图型：", type)
}

export_bundle <- function(bundle, directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  saveRDS(bundle, file.path(directory, "bundle.rds"))
  if (bundle$type == "gsea_collection") {
    write_table(bundle$index, file.path(directory, "gsea_plot_index.csv"))
    for (name in names(bundle$curves)) export_bundle(bundle$curves[[name]], file.path(directory, name))
    return(invisible(NULL))
  }
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
