# 本地基因集分析与 PPI 工作流；不联网获取注释或互作数据。

# 检查当前启用模块需要的包，未启用模块不触发依赖检查。
.require_pathway_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("缺少所选分析模块依赖：", paste(missing, collapse = ", "), call. = FALSE)
}

# 读取 GMT 文件，保留原始 ID 并构建 TERM2GENE 与 TERM2NAME。
.read_local_gmt <- function(path) {
  if (is.null(path) || length(path) != 1L || !file.exists(path)) {
    stop("cfg$pathways$gmt 必须指向存在的本地 GMT 文件。", call. = FALSE)
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  fields <- strsplit(lines, "\t", fixed = FALSE)
  fields <- fields[lengths(fields) >= 3L]
  if (!length(fields)) stop("GMT 文件没有有效的基因集记录。", call. = FALSE)
  term2gene <- do.call(rbind, lapply(fields, function(x) {
    data.frame(term_id = x[[1]], gene = unique(x[-c(1, 2)]), stringsAsFactors = FALSE)
  }))
  term2gene <- unique(term2gene[nzchar(term2gene$gene), , drop = FALSE])
  term2name <- unique(data.frame(term_id = vapply(fields, `[[`, character(1), 1),
                                 description = vapply(fields, `[[`, character(1), 2),
                                 stringsAsFactors = FALSE))
  term2name$description[is.na(term2name$description) | !nzchar(term2name$description) |
                          grepl("^https?://", term2name$description, ignore.case = TRUE)] <-
    term2name$term_id[is.na(term2name$description) | !nzchar(term2name$description) |
                        grepl("^https?://", term2name$description, ignore.case = TRUE)]
  description_counts <- vapply(split(term2name$description, term2name$term_id), function(x) length(unique(x)), integer(1))
  if (any(description_counts > 1L)) stop("GMT 同一 term_id 对应多个 description。", call. = FALSE)
  list(term2gene = term2gene, term2name = term2name)
}

# 将 GMT ID 转成分析使用的 ID，并记录未匹配及重复 symbol 映射。
.map_pathway_ids <- function(gmt, genes, id_type) {
  if (!id_type %in% c("SYMBOL", "gene_id")) stop("gmt_id_type 仅支持 SYMBOL 或 gene_id。", call. = FALSE)
  mapping <- unique(genes[c("gene_id", "gene_name")])
  mapping <- mapping[!is.na(mapping$gene_id) & nzchar(mapping$gene_id), , drop = FALSE]
  if (id_type == "gene_id") {
    gmt$term2gene$analysis_gene <- gmt$term2gene$gene
    report <- data.frame(source_id = unique(gmt$term2gene$gene), analysis_id = unique(gmt$term2gene$gene),
                         status = "gene_id", stringsAsFactors = FALSE)
  } else {
    mapping <- mapping[!is.na(mapping$gene_name) & nzchar(mapping$gene_name), , drop = FALSE]
    symbol_counts <- table(mapping$gene_name)
    duplicates <- names(symbol_counts[symbol_counts > 1L])
    source_ids <- data.frame(source_id = unique(gmt$term2gene$gene), stringsAsFactors = FALSE)
    report <- merge(source_ids, mapping, by.x = "source_id", by.y = "gene_name", all.x = TRUE, sort = FALSE)
    names(report)[names(report) == "gene_id"] <- "analysis_id"
    report$status <- ifelse(is.na(report$analysis_id), "unmatched", "matched")
    report$status[report$source_id %in% duplicates & !is.na(report$analysis_id)] <- "duplicate_symbol"
    gmt$term2gene <- merge(gmt$term2gene, mapping, by.x = "gene", by.y = "gene_name", all = FALSE, sort = FALSE)
    names(gmt$term2gene)[names(gmt$term2gene) == "gene_id"] <- "analysis_gene"
  }
  gmt$term2gene <- unique(gmt$term2gene[c("term_id", "gene", "analysis_gene")])
  list(gmt = gmt, report = report, mapping = mapping)
}

# 用 GMT ID 命名空间准备有序统计量；相同 symbol 保留绝对统计量最大的基因。
.make_ranked_stats <- function(deg, genes, id_type) {
  joined <- deg
  gene_map <- unique(genes[c("gene_id", "gene_name")])
  joined$mapped_name <- gene_map$gene_name[match(joined$gene_id, gene_map$gene_id)]
  if (id_type == "gene_id") joined$rank_id <- joined$gene_id else joined$rank_id <- joined$mapped_name
  joined <- joined[!is.na(joined$rank_id) & nzchar(joined$rank_id) &
                     is.finite(joined$stat) & is.finite(joined$pvalue), , drop = FALSE]
  joined <- joined[order(-abs(joined$stat), joined$rank_id, joined$gene_id), , drop = FALSE]
  joined <- joined[!duplicated(joined$rank_id), , drop = FALSE]
  stats <- stats::setNames(joined$stat, joined$rank_id)
  sort(stats, decreasing = TRUE)
}

# 统一写出 CSV，空结果保留表头供下游流程读取。
.write_pathway_table <- function(data, path) {
  utils::write.csv(data, path, row.names = FALSE, na = "")
  invisible(path)
}

# 在分析 ID 空间内运行 ORA，clusterProfiler 仅用于完整统计，不提前截断显著性。
.run_ora <- function(deg, genes, gmt, cfg, output_dir) {
  tested <- is.finite(deg$stat) & is.finite(deg$pvalue)
  tested_deg <- deg[tested, , drop = FALSE]
  selected <- tested_deg$gene_id[selection_mask(tested_deg, cfg$selection)]
  ids_to_gmt <- function(ids) {
    ids <- as.character(ids[!is.na(ids)])
    if (cfg$pathways$gmt_id_type == "gene_id") return(unique(ids))
    symbols <- genes$gene_name[match(ids, genes$gene_id)]
    unique(symbols[!is.na(symbols) & nzchar(symbols)])
  }
  universe <- ids_to_gmt(tested_deg$gene_id)
  selected <- intersect(ids_to_gmt(selected), unique(gmt$term2gene$gene))
  universe <- intersect(universe, unique(gmt$term2gene$gene))
  term2gene <- data.frame(term_id = gmt$term2gene$term_id, gene = gmt$term2gene$gene)
  term2name <- gmt$term2name
  if (length(selected) && length(universe)) {
    result <- clusterProfiler::enricher(
      gene = selected, universe = universe, TERM2GENE = term2gene,
      TERM2NAME = term2name, pvalueCutoff = 1, qvalueCutoff = 1,
      minGSSize = cfg$pathways$min_size, maxGSSize = cfg$pathways$max_size
    )
    table <- if (is.null(result)) data.frame(
      ID = character(), Description = character(), GeneRatio = character(),
      BgRatio = character(), RichFactor = numeric(), FoldEnrichment = numeric(),
      zScore = numeric(), pvalue = numeric(), p.adjust = numeric(), qvalue = numeric(),
      geneID = character(), Count = integer()
    ) else as.data.frame(result)
  } else table <- data.frame(
    ID = character(), Description = character(), GeneRatio = character(),
    BgRatio = character(), RichFactor = numeric(), FoldEnrichment = numeric(),
    zScore = numeric(), pvalue = numeric(), p.adjust = numeric(), qvalue = numeric(),
    geneID = character(), Count = integer()
  )
  if (nrow(table) && "p.adjust" %in% names(table)) {
    table$significant <- !is.na(table$p.adjust) & table$p.adjust <= cfg$pathways$ora_padj
  }
  .write_pathway_table(table, file.path(output_dir, "ora_results.csv"))
  .write_pathway_table(data.frame(gmt_id = universe), file.path(output_dir, "ora_tested_universe.csv"))
  .write_pathway_table(data.frame(gmt_id = selected), file.path(output_dir, "ora_selected_genes.csv"))
  list(results = table, universe = universe, selected = selected)
}

# fgsea 使用未按 DEG 阈值预筛的完整有效 stat 排序列表。
.run_gsea <- function(deg, genes, gmt, cfg, output_dir) {
  stats <- .make_ranked_stats(deg, genes, cfg$pathways$gmt_id_type)
  gsea_ids <- if (cfg$pathways$gmt_id_type == "SYMBOL") gmt$term2gene$gene else gmt$term2gene$analysis_gene
  pathways <- split(gsea_ids, gmt$term2gene$term_id)
  pathways <- lapply(pathways, unique)
  pathways <- pathways[lengths(lapply(pathways, intersect, y = names(stats))) >= cfg$pathways$min_size &
                         lengths(lapply(pathways, intersect, y = names(stats))) <= cfg$pathways$max_size]
  set.seed(cfg$pathways$seed)
  result <- if (length(pathways)) {
    as.data.frame(fgsea::fgseaMultilevel(
      pathways = pathways, stats = stats,
      minSize = cfg$pathways$min_size, maxSize = cfg$pathways$max_size,
      BPPARAM = BiocParallel::SerialParam()
    ))
  } else data.frame(
    pathway = character(), pval = numeric(), log2err = numeric(), ES = numeric(),
    NES = numeric(), size = integer(), leadingEdge = I(list()), padj = numeric()
  )
  if (nrow(result)) result$significant <- !is.na(result$padj) & result$padj <= cfg$pathways$gsea_padj
  output_table <- result
  if ("leadingEdge" %in% names(output_table)) {
    output_table$leadingEdge <- vapply(output_table$leadingEdge, paste, collapse = ";", character(1))
  }
  .write_pathway_table(output_table, file.path(output_dir, "gsea_results.csv"))
  .write_pathway_table(data.frame(rank_id = names(stats), stat = unname(stats)), file.path(output_dir, "gsea_ranked_stats.csv"))
  list(results = result, ranked_stats = stats, pathways = pathways)
}

# 使用 GSVA 新接口生成样本通路分数，并用 limma 对指定对比完整建模。
.run_gsva <- function(vst, genes, samples, gmt, cfg, output_dir) {
  symbol_map <- unique(genes[c("gene_id", "gene_name")])
  symbol_map <- symbol_map[!is.na(symbol_map$gene_name) & nzchar(symbol_map$gene_name), , drop = FALSE]
  if (cfg$pathways$gmt_id_type == "gene_id") {
    expression <- vst
    expression_ids <- rownames(expression)
    duplicate_selection <- data.frame(gene_name = character(), selected_gene_id = character(),
                                      selected_variance = numeric(), excluded_gene_ids = character())
  } else {
    symbol_map <- symbol_map[symbol_map$gene_id %in% rownames(vst), , drop = FALSE]
    symbol_map$variance <- apply(vst[symbol_map$gene_id, , drop = FALSE], 1, stats::var)
    symbol_map <- symbol_map[order(symbol_map$gene_name, -symbol_map$variance, symbol_map$gene_id), , drop = FALSE]
    selected_symbols <- symbol_map[!duplicated(symbol_map$gene_name), , drop = FALSE]
    duplicate_rows <- Filter(function(group) nrow(group) > 1L, split(symbol_map, symbol_map$gene_name))
    duplicate_selection <- if (length(duplicate_rows)) do.call(rbind, lapply(duplicate_rows, function(group) {
      data.frame(
        gene_name = group$gene_name[[1]], selected_gene_id = group$gene_id[[1]],
        selected_variance = group$variance[[1]],
        excluded_gene_ids = paste(group$gene_id[-1], collapse = ";"),
        stringsAsFactors = FALSE
      )
    })) else data.frame(gene_name = character(), selected_gene_id = character(),
                        selected_variance = numeric(), excluded_gene_ids = character())
    expression <- vst[selected_symbols$gene_id, , drop = FALSE]
    rownames(expression) <- selected_symbols$gene_name
    expression_ids <- rownames(expression)
  }
  .write_pathway_table(duplicate_selection, file.path(output_dir, "gsva_duplicate_symbol_selection.csv"))
  gsva_ids <- if (cfg$pathways$gmt_id_type == "SYMBOL") gmt$term2gene$gene else gmt$term2gene$analysis_gene
  gene_sets <- split(gsva_ids, gmt$term2gene$term_id)
  gene_sets <- lapply(gene_sets, function(x) intersect(unique(x), expression_ids))
  gene_sets <- gene_sets[lengths(gene_sets) >= cfg$pathways$min_size & lengths(gene_sets) <= cfg$pathways$max_size]
  if (length(gene_sets)) {
    params <- GSVA::gsvaParam(
      expression, gene_sets, kcdf = "Gaussian",
      minSize = cfg$pathways$min_size, maxSize = cfg$pathways$max_size
    )
    scores <- GSVA::gsva(params, BPPARAM = BiocParallel::SerialParam())
  } else scores <- matrix(numeric(), nrow = 0L, ncol = ncol(expression), dimnames = list(character(), colnames(expression)))
  samples <- samples[match(colnames(vst), samples$sample_id), , drop = FALSE]
  samples$condition <- factor(samples$condition, levels = cfg$analysis$condition_levels)
  samples$batch <- factor(samples$batch)
  design_info <- make_design(samples, cfg)
  samples <- design_info$samples
  design <- design_info$matrix
  if (!nrow(scores)) {
    results <- data.frame(term_id = character(), description = character(), logFC = numeric(),
                          AveExpr = numeric(), t = numeric(), P.Value = numeric(), adj.P.Val = numeric(),
                          B = numeric())
    .write_pathway_table(data.frame(term_id = character(), scores, check.names = FALSE), file.path(output_dir, "gsva_scores.csv"))
    .write_pathway_table(results, file.path(output_dir, "gsva_limma_results.csv"))
    saveRDS(scores, file.path(output_dir, "gsva_scores.rds"))
    return(list(scores = scores, results = results, design = design))
  }
  contrast_samples <- samples[rep(1L, 2L), , drop = FALSE]
  contrast_samples$condition <- factor(
    c(cfg$contrast$numerator, cfg$contrast$denominator),
    levels = levels(samples$condition)
  )
  contrast_rows <- stats::model.matrix(design_info$formula, data = contrast_samples)
  contrast <- matrix(
    contrast_rows[1, colnames(design), drop = FALSE] - contrast_rows[2, colnames(design), drop = FALSE],
    ncol = 1L, dimnames = list(colnames(design), "numerator_minus_denominator")
  )
  fit <- limma::lmFit(scores, design)
  fit <- limma::contrasts.fit(fit, contrast)
  fit <- limma::eBayes(fit)
  results <- limma::topTable(fit, number = Inf, sort.by = "none")
  results$term_id <- rownames(results)
  results <- merge(gmt$term2name, results, by = "term_id", all.y = TRUE, sort = FALSE)
  results <- results[c("term_id", "description", setdiff(names(results), c("term_id", "description")))]
  score_table <- data.frame(term_id = rownames(scores), scores, check.names = FALSE)
  .write_pathway_table(score_table, file.path(output_dir, "gsva_scores.csv"))
  .write_pathway_table(results, file.path(output_dir, "gsva_limma_results.csv"))
  saveRDS(scores, file.path(output_dir, "gsva_scores.rds"))
  list(scores = scores, results = results, design = design)
}

# 只使用本地 STRING 风格边表，并为显著差异基因生成可复现布局坐标。
.run_ppi <- function(deg, cfg, output_dir) {
  edges_path <- cfg$pathways$ppi_edges
  if (is.null(edges_path) || !file.exists(edges_path)) stop("启用 PPI 时需提供本地 cfg$pathways$ppi_edges CSV。", call. = FALSE)
  edges <- read_table(edges_path)
  required <- c("from", "to", "score")
  if (!all(required %in% names(edges))) stop("PPI CSV 需包含 from、to、score 列。", call. = FALSE)
  edges$score <- as.numeric(edges$score)
  if (any(!is.finite(edges$score) | edges$score < 0 | edges$score > 1)) {
    stop("PPI score 必须是 [0,1] 内的有限数值。", call. = FALSE)
  }
  edges <- edges[edges$score >= cfg$pathways$ppi_score & edges$from != edges$to, , drop = FALSE]
  # 同一无向边重复出现时保留最高置信度，避免结果取决于输入行顺序。
  edges <- edges[order(edges$score, decreasing = TRUE), , drop = FALSE]
  edge_key <- vapply(seq_len(nrow(edges)), function(i) paste(sort(c(edges$from[[i]], edges$to[[i]])), collapse = "\r"), character(1))
  edges <- edges[!duplicated(edge_key), , drop = FALSE]
  selected <- deg[selection_mask(deg, cfg$selection), , drop = FALSE]
  selected <- selected[!duplicated(selected$gene_id), , drop = FALSE]
  ids <- unique(as.character(selected$gene_id))
  edges <- edges[edges$from %in% ids & edges$to %in% ids, , drop = FALSE]
  nodes <- merge(data.frame(gene_id = ids), selected[c("gene_id", "gene_name", "log2FoldChange")], by = "gene_id", all.x = TRUE, sort = FALSE)
  if (nrow(nodes)) {
    graph <- igraph::graph_from_data_frame(edges[c("from", "to", "score")], directed = FALSE, vertices = data.frame(name = nodes$gene_id))
    degree <- igraph::degree(graph)
    if (nrow(nodes) == 1L) {
      coordinates <- matrix(c(0, 0), nrow = 1L)
    } else {
      set.seed(cfg$pathways$seed)
      coordinates <- igraph::layout_with_fr(graph)
    }
    vertex_names <- igraph::V(graph)$name
    nodes <- nodes[match(vertex_names, nodes$gene_id), , drop = FALSE]
    nodes$x <- coordinates[match(nodes$gene_id, vertex_names), 1]
    nodes$y <- coordinates[match(nodes$gene_id, vertex_names), 2]
    nodes$degree <- unname(degree[match(nodes$gene_id, names(degree))])
    nodes$label <- ifelse(is.na(nodes$gene_name) | nodes$gene_name == "", nodes$gene_id, nodes$gene_name)
  } else {
    nodes$x <- numeric()
    nodes$y <- numeric()
    nodes$degree <- integer()
    nodes$label <- character()
  }
  .write_pathway_table(nodes, file.path(output_dir, "ppi_nodes.csv"))
  .write_pathway_table(edges, file.path(output_dir, "ppi_edges.csv"))
  saveRDS(list(nodes = nodes, edges = edges), file.path(output_dir, "ppi_network.rds"))
  list(nodes = nodes, edges = edges)
}

# 按配置运行选定模块，返回各模块结果、基因集和 ID 映射报告。
analyze_pathways <- function(analysis, cfg, output_dir = ".") {
  required_deg <- c("gene_id", "gene_name", "stat", "log2FoldChange", "padj", "pvalue")
  if (!all(required_deg %in% names(analysis$deg))) stop("analysis$deg 缺少必要列。", call. = FALSE)
  if (is.null(rownames(analysis$vst))) stop("analysis$vst 行名需为 gene_id。", call. = FALSE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  enabled <- unique(cfg$pathways$enabled)
  available <- c("ora", "gsea", "gsva", "ppi")
  if (!all(enabled %in% available)) stop("pathways$enabled 包含不支持的模块。", call. = FALSE)
  package_map <- list(
    ora = "clusterProfiler", gsea = c("fgsea", "BiocParallel"),
    gsva = c("GSVA", "BiocParallel", "limma"), ppi = "igraph"
  )
  .require_pathway_packages(unique(unlist(package_map[enabled])))
  needs_gmt <- any(enabled %in% c("ora", "gsea", "gsva"))
  if (needs_gmt) {
    gmt <- .read_local_gmt(cfg$pathways$gmt)
    mapped <- .map_pathway_ids(gmt, analysis$genes, cfg$pathways$gmt_id_type)
    gmt <- mapped$gmt
    annotation_universe <- unique(gmt$term2gene$analysis_gene)
    .write_pathway_table(mapped$report, file.path(output_dir, "id_mapping_report.csv"))
    .write_pathway_table(gmt$term2gene, file.path(output_dir, "gene_sets.csv"))
    saveRDS(list(gene_sets = split(gmt$term2gene$analysis_gene, gmt$term2gene$term_id), annotation_universe = annotation_universe),
            file.path(output_dir, "gene_sets_universe.rds"))
    results <- list(id_mapping_report = mapped$report, gene_sets = gmt$term2gene, annotation_universe = annotation_universe)
  } else {
    gmt <- NULL
    results <- list(id_mapping_report = data.frame(), gene_sets = data.frame(), annotation_universe = character())
  }
  if ("ora" %in% enabled) results$ora <- .run_ora(analysis$deg, analysis$genes, gmt, cfg, output_dir)
  if ("gsea" %in% enabled) results$gsea <- .run_gsea(analysis$deg, analysis$genes, gmt, cfg, output_dir)
  if ("gsva" %in% enabled) results$gsva <- .run_gsva(analysis$vst, analysis$genes, analysis$samples, gmt, cfg, output_dir)
  if ("ppi" %in% enabled) results$ppi <- .run_ppi(analysis$deg, cfg, output_dir)
  results
}
