# 计算层仅由独立 worker 调用；重用项目模块，不在界面线程执行分析。
tb_engine <- function(root) {
  environment <- new.env(parent = globalenv())
  for (file in c("core.R", "analysis.R", "prepare.R", "pathways.R", "ppi_prepare.R", "plots.R")) {
    sys.source(file.path(root, "R", file), envir = environment)
  }
  require_packages <- environment$require_packages
  environment$require_packages <- function(packages) tryCatch(require_packages(packages), error = function(e)
    tb_fail("BW-R03", conditionMessage(e), hint = "在系统设置中检查当前 R 环境及所需 R 包。", parent = e))
  import <- environment$import_dataset
  environment$import_dataset <- function(cfg, samples) {
    if (cfg$input$mode != "counts") return(import(cfg, samples))
    tb_with_input(c(cfg$input$counts, cfg$input$original_groups), import(cfg, samples), "BW-I04")
  }
  read_gmt <- environment$.read_local_gmt
  environment$.read_local_gmt <- function(path) tb_with_input(path, read_gmt(path))
  environment
}

tb_samples <- function(path, parameters) {
  samples <- tb_with_input(path, tb_read_groups(path))
  levels <- parameters$model_groups
  if (!length(levels)) levels <- c(parameters$control, parameters$treatment)
  samples <- samples[samples$condition %in% levels, , drop = FALSE]
  if (!all(levels %in% samples$condition)) tb_fail("BW-I03", "部分分析组未匹配分组表。", path,
    "请核对分组表的组名与当前选择的对照、处理组。")
  samples
}

tb_config <- function(spec, root, directory, engine, with_samples = TRUE) {
  cfg <- engine$load_config(file.path(root, "config", "project.R"))
  p <- spec$params
  cfg$project$species <- c(human = "Homo_sapiens", mouse = "Mus_musculus")[[p$species]]
  if (with_samples) {
    samples <- tb_samples(spec$inputs$groups, p)
    sample_path <- file.path(directory, "inputs", "sample_mapping.csv")
    engine$write_table(samples, sample_path)
    cfg$input$mode <- "counts"
    cfg$input$counts <- spec$inputs$counts
    cfg$input$samples <- sample_path
    cfg$input$original_groups <- spec$inputs$groups
    cfg$input$genes <- NULL
    cfg$project$max_samples <- nrow(samples)
  }
  cfg$project$output <- file.path(directory, "outputs")
  cfg$analysis$condition_levels <- if (length(p$model_groups)) p$model_groups else c(p$control, p$treatment)
  cfg$contrast <- list(numerator = p$treatment, denominator = p$control)
  cfg$analysis$min_count <- as.integer(p$min_count)
  cfg$analysis$min_samples <- as.integer(p$min_samples)
  cfg$analysis$alpha <- p$alpha
  cfg$analysis$fit_type <- p$fit_type
  cfg$analysis$use_batch <- isTRUE(p$use_batch)
  covariates <- trimws(unlist(strsplit(p$covariates, ",", fixed = TRUE)))
  cfg$analysis$covariates <- covariates[nzchar(covariates)]
  cfg$selection$padj_cutoff <- p$padj
  cfg$selection$log2fc_cutoff <- p$log2fc
  cfg$selection$direction <- p$direction
  cfg$selection$pca_top_genes <- as.integer(p$pca_top)
  cfg$selection$pca_scale <- isTRUE(p$pca_scale)
  cfg$selection$heatmap_top_n <- as.integer(p$heatmap_top)
  cfg$selection$heatmap_mode <- p$heatmap_mode
  cfg$selection$row_zscore <- isTRUE(p$row_scale)
  cfg$selection$cluster_rows <- isTRUE(p$cluster_rows)
  cfg$selection$cluster_columns <- isTRUE(p$cluster_columns)
  cfg$selection$column_cluster_mode <- p$column_cluster_mode
  cfg$selection$distance <- p$distance
  cfg$selection$linkage <- p$linkage
  cfg$selection$pathway_top_n <- as.integer(p$pathway_top)
  cfg$selection$gsea_sort <- p$gsea_sort
  cfg$selection$gsea_order <- p$gsea_order
  cfg$selection$pathway_terms <- tb_parse_terms(p$pathway_terms)
  cfg$selection$pathway_id <- if (nzchar(p$pathway_id)) p$pathway_id else NULL
  cfg$selection$label_top_n <- if (isTRUE(p$labels)) 8L else 0L
  cfg$pathways$min_size <- as.integer(p$min_set_size)
  cfg$pathways$max_size <- as.integer(p$max_set_size)
  cfg$pathways$gmt_id_type <- p$gmt_id_type
  cfg$pathways$gmt <- if (nzchar(spec$inputs$gmt)) spec$inputs$gmt else NULL
  cfg$pathways$database_label <- if (spec$tool == "go") paste0("GO_", paste(p$go_ontology, collapse = "+")) else if (spec$tool == "kegg") "KEGG" else "user_GMT"
  cfg$pathways$database_version <- p$database_version
  cfg$pathways$ora_padj <- p$ora_fdr
  cfg$pathways$gsea_padj <- p$padj
  cfg$pathways$ppi_edges <- spec$inputs$edges
  cfg$pathways$ppi_score <- p$ppi_score
  cfg$pathways$ppi_score_scale <- p$network_score_scale
  cfg$pathways$ppi_layout <- p$network_layout
  cfg$pathways$ppi_require_edges <- p$ppi_require_edges
  cfg$style <- utils::modifyList(cfg$style, spec$style)
  cfg$style$colors <- c(Up = spec$style$up, Down = spec$style$down,
                         Not_significant = spec$style$neutral)
  cfg$style$show_sample_labels <- isTRUE(p$labels)
  cfg$style$group_colors <- stats::setNames(c(spec$style$down, spec$style$up), c(p$control, p$treatment))
  cfg$style$formats <- spec$style$formats
  cfg
}

tb_processed_expression <- function(spec, cfg, engine) {
  values <- tb_read_matrix(spec$inputs$matrix, list(matrix_transform = "none"))
  samples <- tb_with_input(spec$inputs$groups, engine$read_samples(cfg))
  columns <- match(samples$sample_id, colnames(values))
  missing <- is.na(columns)
  columns[missing] <- match(samples$source_sample_id[missing], colnames(values))
  if (anyNA(columns) || anyDuplicated(columns)) tb_fail("BW-I04", "表达矩阵样本列须唯一对应分组表中的 sample_id 或原始样本名。",
    c(spec$inputs$matrix, spec$inputs$groups), "核对两张表的样本 ID、空格和重复列。")
  values <- values[, columns, drop = FALSE]
  colnames(values) <- samples$sample_id
  deg <- if (nzchar(spec$inputs$deg)) tb_with_input(spec$inputs$deg, tb_prepare_deg(spec$inputs$deg))
  ids <- rownames(values)
  gene_names <- if (is.null(deg)) ids else as.character(deg$gene_name[match(ids, deg$gene_id)])
  missing <- is.na(gene_names) | !nzchar(gene_names)
  gene_names[missing] <- ids[missing]
  list(vst = values, counts = values, samples = samples, deg = deg,
    genes = data.frame(gene_id = ids, gene_name = gene_names, row.names = ids))
}

tb_model <- function(cfg, engine, root, directory) {
  engine$require_packages(c("DESeq2", "SummarizedExperiment", "digest", "jsonlite"))
  samples <- tb_with_input(cfg$input$original_groups, engine$read_samples(cfg))
  tb_with_input(cfg$input$original_groups, engine$make_design(samples, cfg))
  fingerprint <- list(counts = digest::digest(file = cfg$input$counts, algo = "sha256"),
                       species = cfg$project$species, samples = samples, analysis = cfg$analysis,
                       gene_id_col = cfg$input$gene_id_col, gene_name_col = cfg$input$gene_name_col,
                       R = as.character(getRversion()),
                       packages = engine$package_versions(c("DESeq2", "SummarizedExperiment")),
                       code = engine$file_fingerprint(file.path(root, "R", c("core.R", "analysis.R"))))
  key <- digest::digest(fingerprint, algo = "sha256")
  cache <- file.path(root, "results", "toolbox", "cache")
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(cache, paste0(key, ".rds"))
  if (file.exists(path)) {
    message("复用基础模型：", substr(key, 1, 16))
    analysis <- readRDS(path)
    if (!identical(analysis$config$contrast, cfg$contrast))
      analysis$deg <- engine$extract_degs(analysis$dds, analysis$genes, cfg)
  } else {
    tb_status_write(directory, "running", 25, "正在拟合 DESeq2 模型与 VST；日志显示实际进展。")
    working <- file.path(directory, "working", "model")
    analysis <- engine$analyze_dataset(cfg, samples, working, fingerprint)
    temporary <- file.path(cache, paste0(key, "-", basename(directory), ".tmp"))
    saveRDS(analysis, temporary)
    # 完整写入后才发布缓存；并发重复计算不让其他任务读到半写入 RDS。
    if (file.exists(path)) unlink(temporary) else if (!file.rename(temporary, path)) {
      stop("无法发布完整模型缓存：", path)
    }
  }
  analysis$config <- cfg
  engine$write_table(analysis$samples, file.path(directory, "outputs", "sample_mapping.csv"))
  analysis
}


tb_prepare_deg <- function(path, cfg = NULL, ranked = FALSE) {
  data <- tb_read_preview(path, n = -1)
  if (!"log2FoldChange" %in% names(data) && "log2FC" %in% names(data)) data$log2FoldChange <- data$log2FC
  if (!"gene_id" %in% names(data) && "rank_id" %in% names(data)) data$gene_id <- data$rank_id
  if (!"gene_id" %in% names(data)) stop("输入表缺少 gene_id。")
  data$gene_id <- trimws(as.character(data$gene_id))
  if (anyNA(data$gene_id) || any(!nzchar(trimws(data$gene_id))) || anyDuplicated(data$gene_id)) {
    stop("差异表 gene_id 必须非空且唯一。")
  }
  if (!"gene_name" %in% names(data)) data$gene_name <- data$gene_id
  if (ranked && !"stat" %in% names(data)) {
    score <- intersect(c("score", "rank_score"), names(data))
    if (length(score)) data$stat <- data[[score[1L]]]
  }
  needed <- if (ranked) "stat" else "log2FoldChange"
  if (!all(needed %in% names(data))) stop("缺少 ", needed, if (ranked) "（或 score / rank_score）" else "（或 log2FC）")
  if (!ranked && !any(c("padj", "pvalue") %in% names(data))) stop("差异表需含 padj 或完整表的 pvalue。")
  for (column in intersect(c("log2FoldChange", "padj", "pvalue", "stat"), names(data))) {
    converted <- suppressWarnings(as.numeric(data[[column]]))
    bad <- is.na(converted) & !is.na(data[[column]]) & nzchar(as.character(data[[column]]))
    if (any(bad)) stop("差异表数值列含非数值：", column)
    data[[column]] <- converted
    if (any(is.infinite(converted))) stop("差异表数值不能为 Inf：", column)
  }
  for (column in intersect(c("pvalue", "padj"), names(data))) {
    if (any(data[[column]] < 0 | data[[column]] > 1, na.rm = TRUE)) stop(column, " 须位于 [0,1] 或为 NA。")
  }
  if (!ranked && !"padj" %in% names(data)) data$padj <- stats::p.adjust(data$pvalue, method = "BH")
  if (ranked && sum(is.finite(data$stat)) < 2L) stop("排序表至少需要两个有限的有符号统计量。")
  data
}

tb_selection_output <- function(analysis, cfg, directory, engine) {
  selected <- analysis$deg[engine$selection_mask(analysis$deg, cfg$selection), , drop = FALSE]
  selected <- selected[order(selected$padj, -abs(selected$log2FoldChange)), , drop = FALSE]
  engine$write_table(analysis$deg, file.path(directory, "outputs", "deg_all.csv"))
  engine$write_table(selected, file.path(directory, "outputs", "deg_selected.csv"))
  summary <- data.frame(numerator = cfg$contrast$numerator, denominator = cfg$contrast$denominator,
                         tested = nrow(analysis$deg), selected = nrow(selected),
                         up = sum(selected$log2FoldChange > 0), down = sum(selected$log2FoldChange < 0),
                         padj = cfg$selection$padj_cutoff, log2fc = cfg$selection$log2fc_cutoff)
  engine$write_table(summary, file.path(directory, "outputs", "deg_summary.csv"))
  summary
}

tb_run_legacy <- function(script, overrides, normalize_counts = FALSE) {
  # 只替换已知配置赋值；保留源脚本的算法和布局，绝不以正则改写 R 代码。
  expressions <- parse(file = script, encoding = "UTF-8")
  environment <- new.env(parent = globalenv())
  list2env(overrides, envir = environment)
  previous <- getwd()
  on.exit(setwd(previous), add = TRUE)
  for (index in seq_along(expressions)) {
    expression <- expressions[[index]]
    assignment <- is.call(expression) && identical(expression[[1]], as.name("<-")) && is.symbol(expression[[2]])
    name <- if (assignment) as.character(expression[[2]]) else ""
    boundary <- if (normalize_counts) "group_values" else "auto_process_colors"
    if (name == boundary) {
      return(list(type = "legacy_heatmap", context = environment, expressions = expressions[index:length(expressions)]))
    }
    condition <- if (is.call(expression) && identical(expression[[1]], as.name("if"))) expression[[2]] else NULL
    is_normalization <- is.call(condition) && identical(condition[[1]], as.name("==")) &&
      identical(condition[[2]], as.name("normalization_method"))
    if (normalize_counts && is_normalization) {
      # 原脚本在选择目标基因后计算 CPM/VST；工作台改为完整文库转换后再取目标基因。
      environment$norm <- tb_custom_normalization(environment)
    } else if (name %in% names(overrides)) {
      value <- overrides[[name]]
      if (is.function(value)) environment(value) <- environment
      assign(name, value, envir = environment)
    } else eval(expression, environment)
  }
  stop("找不到旧版热图的绘图边界。")
}

tb_custom_normalization <- function(context) {
  method <- context$normalization_method
  selected <- context$mat
  if (any(!is.finite(selected)) || any(selected < 0)) stop("Count 必须为非负有限数值。")
  if (method == "none") return(selected)
  if (method == "log2") return(log2(selected + context$pseudo_count))
  full <- as.matrix(context$counts_df[, context$samples, drop = FALSE])
  storage.mode(full) <- "numeric"
  if (any(!is.finite(full)) || any(full < 0)) stop("Count 必须为非负有限数值。")
  if (method == "log_cpm") {
    library <- colSums(full)
    if (any(library <= 0)) stop("CPM 需要非零完整文库。")
    return(log2(sweep(selected, 2, library, "/") * 1e6 + context$pseudo_count))
  }
  if (method != "vst") stop("Count 热图仅支持 log2/log_cpm/vst/none。")
  if (any(full != round(full))) stop("VST 只接受原始整数 Count。")
  if (!requireNamespace("DESeq2", quietly = TRUE)) stop("VST 需要 DESeq2。")
  ids <- if (!is.na(context$gene_id_col)) as.character(context$counts_df[[context$gene_id_col]]) else as.character(seq_len(nrow(full)))
  if (anyDuplicated(ids)) stop("完整矩阵 gene_id 重复，不能拟合 VST。")
  rownames(full) <- ids
  nonzero <- rowSums(full) > 0
  column_data <- data.frame(Group = context$meta[[context$group_col]], row.names = context$samples)
  dds <- DESeq2::DESeqDataSetFromMatrix(full[nonzero, , drop = FALSE], column_data, design = ~Group)
  transformed <- SummarizedExperiment::assay(DESeq2::varianceStabilizingTransformation(dds, blind = context$vst_blind))
  # 原脚本 max_mean/mean/sum 处理可能合并 Symbol；VST 不对不同稳定 ID 默合并。
  chosen <- context$selected
  if (context$duplicate_gene_method == "max_mean") chosen <- chosen[context$ord, , drop = FALSE]
  selected_ids <- if (!is.na(context$gene_id_col)) as.character(chosen[[context$gene_id_col]]) else NULL
  if (is.null(selected_ids) || nrow(selected) != length(selected_ids) ||
      !all(selected_ids %in% rownames(transformed))) stop("VST 需要可唯一映射的 gene_id；合并 Symbol 请使用 log2/log-CPM。")
  result <- transformed[selected_ids, , drop = FALSE]
  rownames(result) <- rownames(selected)
  result
}

tb_legacy_heatmap <- function(spec, cfg, analysis, root, directory, engine) {
  output <- file.path(directory, "outputs")
  samples <- tb_samples(spec$inputs$groups, spec$params)
  metadata <- data.frame(Sample = samples$source_sample_id, Group = samples$condition)
  group_path <- file.path(directory, "inputs", "legacy_groups.csv")
  engine$write_table(metadata, group_path)
  overrides <- list(work_dir = dirname(root), output_dir = output,
    group_file = group_path, metadata_file = group_path,
    selected_groups = if (spec$tool == "custom_heatmap") unique(samples$condition)
      else c(spec$params$control, spec$params$treatment),
    cluster_rows = spec$params$cluster_rows, cluster_columns = spec$params$cluster_columns,
    heatmap_scale = if (spec$params$row_scale) "row" else "none",
    cluster_within_process = spec$params$cluster_rows,
    pseudo_count = spec$params$log_pseudocount, min_total_count = spec$params$min_count)
  if (spec$tool == "custom_heatmap") {
    targets <- tb_read_preview(spec$inputs$targets, n = -1)
    column <- intersect(c("GeneKey", "gene_name", "GeneSymbol", names(targets)[1]), names(targets))[1]
    if ("Use" %in% names(targets)) targets <- targets[toupper(targets$Use) != "FALSE", , drop = FALSE]
    overrides$count_file <- spec$inputs$counts
    overrides$target_genes <- unique(trimws(as.character(targets[[column]])))
    overrides$normalization_method <- spec$params$custom_transform
    script <- "04.4_custom_gene_count_heatmap.R"
  } else {
    deg <- analysis$deg
    excluded <- engine$heatmap_gene_exclusions(deg$gene_id, deg$gene_name)
    engine$write_table(excluded, file.path(output, "excluded_genes.csv"))
    deg <- deg[!deg$gene_id %in% excluded$gene_id, , drop = FALSE]
    overrides$distance_rows <- overrides$distance_columns <- spec$params$distance
    overrides$group_mean_distance <- spec$params$distance
    overrides$clustering_method <- spec$params$linkage
    if (nzchar(spec$inputs$matrix)) deg <- deg[deg$gene_id %in% rownames(analysis$counts), , drop = FALSE]
    raw <- analysis$counts[deg$gene_id, , drop = FALSE]
    source_names <- analysis$samples$source_sample_id[match(colnames(raw), analysis$samples$sample_id)]
    colnames(raw) <- source_names
    deg$log2FC <- deg$log2FoldChange
    table <- cbind(deg, as.data.frame(raw, check.names = FALSE))
    expression_path <- file.path(directory, "inputs", "manual_expression.csv")
    engine$write_table(table, expression_path)
    if (nzchar(spec$inputs$matrix)) {
      overrides$normalization_method <- "none"
      overrides$min_total_count <- -Inf
    }
    overrides$expression_file <- expression_path
    overrides$manual_annotation_file <- spec$inputs$annotation
    overrides$padj_cutoff <- spec$params$padj
    overrides$log2fc_cutoff <- spec$params$log2fc
    overrides$top_n_genes <- as.integer(spec$params$heatmap_top)
    script <- "04.3_manual_pathway_heatmap.R"
  }
  engine$require_packages(c("ComplexHeatmap", "circlize", "svglite"))
  source <- file.path(dirname(root), "legacy", script)
  # 当前脚本身份写入结果，便于区分后续用户修改版本。
  engine$write_manifest(list(source = source, sha256 = digest::digest(file = source, algo = "sha256"),
                              overrides = overrides[!vapply(overrides, is.function, logical(1))]), file.path(output, "source_adapter.json"))
  tb_run_legacy(source, overrides, normalize_counts = spec$tool == "custom_heatmap")
}

tb_read_matrix <- function(path, parameters) tb_with_input(path, {
  table <- tb_read_preview(path, n = -1)
  if (ncol(table) < 3 || nrow(table) < 2) stop("矩阵至少需要一个 ID 列、两个数值列和两行。")
  ids <- as.character(table[[1]])
  if (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids)) stop("矩阵首列 ID 必须非空且唯一。")
  matrix <- as.matrix(table[, -1, drop = FALSE])
  suppressWarnings(storage.mode(matrix) <- "numeric")
  if (any(!is.finite(matrix))) stop("首列后必须全部为有限数值；请移除 gene_name 等注释列。")
  rownames(matrix) <- ids
  if (parameters$matrix_transform == "log2") {
    if (parameters$log_pseudocount <= 0 || any(matrix < 0)) stop("log2 要求非负输入和正伪计数。")
    matrix <- log2(matrix + parameters$log_pseudocount)
  } else if (parameters$matrix_transform != "none") stop("通用矩阵只支持 none/log2。")
  matrix
})

tb_matrix_bundle <- function(spec, engine) {
  matrix <- tb_read_matrix(spec$inputs$matrix, spec$params)
  metadata <- data.frame(sample_id = colnames(matrix), condition = "Samples", batch = "not_applicable",
                         row.names = colnames(matrix))
  if (isTRUE(spec$params$matrix_use_groups) && nzchar(spec$inputs$groups)) {
    groups <- tb_read_preview(spec$inputs$groups, n = -1)
    id_column <- intersect(c("Sample", "source_sample_id", "sample_id"), names(groups))[1]
    group_column <- intersect(c("Group", "condition"), names(groups))[1]
    if (is.na(id_column) || is.na(group_column)) tb_fail("BW-I03", "分组表需含 Sample/Group 或 sample_id/condition。", spec$inputs$groups)
    if (anyDuplicated(groups[[id_column]]) || !all(colnames(matrix) %in% groups[[id_column]])) tb_fail("BW-I04", "分组表必须唯一覆盖全部矩阵样本。",
      c(spec$inputs$groups, spec$inputs$matrix), "核对两张表的样本名称及分组表中的重复记录。")
    metadata$condition <- groups[[group_column]][match(colnames(matrix), groups[[id_column]])]
  }
  genes <- data.frame(gene_id = rownames(matrix), gene_name = rownames(matrix), row.names = rownames(matrix))
  analysis <- list(vst = matrix, genes = genes, samples = metadata)
  selection <- list(use_batch_visualization = FALSE, pca_top_genes = nrow(matrix),
                      pca_scale = spec$params$pca_scale, heatmap_mode = "variable",
                      heatmap_top_n = min(nrow(matrix), spec$params$heatmap_top), row_zscore = spec$params$row_scale,
                      cluster_rows = spec$params$cluster_rows, cluster_columns = spec$params$cluster_columns,
                      distance = spec$params$distance, linkage = spec$params$linkage,
                      column_cluster_mode = spec$params$column_cluster_mode, sanitize_genes = FALSE)
  bundle <- engine$prepare_bundle(analysis, list(selection = selection),
                                   if (spec$tool == "matrix_pca") "pca" else "heatmap")
  if (spec$tool == "matrix_heatmap") {
    bundle$extras$matrix_units <- if (spec$params$row_scale) "row_zscore" else spec$params$matrix_transform
    if (!isTRUE(spec$params$matrix_use_groups)) bundle$extras$sample_annotation <- NULL
  }
  bundle
}

tb_prepare_circos <- function(spec, output, engine) {
  chromosomes <- tb_read_preview(spec$inputs$chromosomes, n = -1)
  if (!all(c("chr", "length") %in% names(chromosomes))) tb_fail("BW-I03", "染色体 CSV/TSV 需含表头 chr,length。", spec$inputs$chromosomes)
  if (anyDuplicated(chromosomes$chr) || any(!nzchar(chromosomes$chr)) ||
      any(!is.finite(chromosomes$length)) || any(chromosomes$length <= 0)) tb_fail("BW-I03", "染色体名称必须唯一，长度必须为正数。", spec$inputs$chromosomes)
  regions <- function(path, required) {
    if (!nzchar(path)) return(NULL)
    data <- tb_read_preview(path, n = -1)
    if (!all(required %in% names(data))) tb_fail("BW-I03", paste("区域文件缺少列：", paste(setdiff(required, names(data)), collapse = ", ")), path)
    data
  }
  features <- regions(spec$inputs$features, c("chr", "start", "end", "label"))
  links <- regions(spec$inputs$links, c("chr1", "start1", "end1", "chr2", "start2", "end2"))
  check_regions <- function(chr, start, end, path) {
    max_length <- chromosomes$length[match(chr, chromosomes$chr)]
    if (anyNA(max_length) || any(!is.finite(start)) || any(!is.finite(end)) ||
        any(start < 0 | end <= start | end > max_length)) tb_fail("BW-I04", "区域须匹配染色体，且满足 0 <= start < end <= length。", c(path, spec$inputs$chromosomes))
  }
  if (!is.null(features)) check_regions(features$chr, features$start, features$end, spec$inputs$features)
  if (!is.null(links)) {
    check_regions(links$chr1, links$start1, links$end1, spec$inputs$links)
    check_regions(links$chr2, links$start2, links$end2, spec$inputs$links)
  }
  engine$write_table(chromosomes, file.path(output, "plot_data.csv"))
  if (!is.null(features)) engine$write_table(features, file.path(output, "features.csv"))
  if (!is.null(links)) engine$write_table(links, file.path(output, "links.csv"))
  list(type = "circos", data = chromosomes, extras = list(features = features, links = links))
}

tb_network_matrices <- function(analysis, pathways, output, engine, dense_node_limit = 2000L) {
  nodes <- pathways$ppi$nodes
  edges <- pathways$ppi$edges
  if (!nrow(nodes)) return(invisible(NULL))
  ids <- nodes$gene_id
  if (!is.null(analysis$counts)) {
    count <- analysis$counts[ids, , drop = FALSE]
    engine$write_table(data.frame(gene_id = ids, count, check.names = FALSE), file.path(output, "ppi_node_counts.csv"))
  }
  # 大网络使用稀疏矩阵，避免选中大量孤立节点时构建两个 N² 稠密矩阵。
  if (length(ids) > dense_node_limit) {
    engine$require_packages("Matrix")
    from <- match(edges$from, ids)
    to <- match(edges$to, ids)
    weighted <- Matrix::sparseMatrix(i = c(from, to), j = c(to, from),
      x = rep(edges$score, 2), dims = c(length(ids), length(ids)), dimnames = list(ids, ids))
    saveRDS(list(weighted = weighted, binary = 1L * (weighted > 0)), file.path(output, "ppi_sparse_matrices.rds"))
    engine$write_manifest(list(format = "sparse", nodes = length(ids), dense_node_limit = dense_node_limit,
                                note = "完整非零元素见 ppi_edges.csv；未生成巨大稠密 CSV。"),
                           file.path(output, "ppi_matrix_note.json"))
    return(invisible(NULL))
  }
  weighted <- matrix(0, length(ids), length(ids), dimnames = list(ids, ids))
  for (i in seq_len(nrow(edges))) {
    weighted[edges$from[i], edges$to[i]] <- edges$score[i]
    weighted[edges$to[i], edges$from[i]] <- edges$score[i]
  }
  engine$write_table(data.frame(gene_id = ids, weighted, check.names = FALSE), file.path(output, "ppi_weighted_matrix.csv"))
  engine$write_table(data.frame(gene_id = ids, 1L * (weighted > 0), check.names = FALSE), file.path(output, "ppi_binary_matrix.csv"))
}

tb_run_request <- function(spec, root, directory) {
  spec <- tb_normalize_spec(spec, root)
  tb_validate_inputs(spec, root)
  plan <- tb_group_plan(spec)
  if (!is.null(plan$pairs)) return(tb_run_comparisons(spec, plan, root, directory))
  if (!is.null(plan)) {
    spec$params$model_groups <- plan$groups
    spec$params$control <- plan$groups[1L]
    spec$params$treatment <- plan$groups[2L]
  }
  engine <- tb_engine(root)
  engine$require_packages(c("jsonlite", "digest"))
  output <- file.path(directory, "outputs")
  dir.create(output, showWarnings = FALSE)
  tb_status_write(directory, "running", 10, "读取参数与输入快照。")
  tb_write_reproduce(spec, file.path(directory, "reproduce.R"), root)
  bundle <- NULL
  cfg <- NULL
  if (spec$tool == "figure_layout") {
    bundle <- tb_prepare_figure(spec)
    if (!is.null(spec$bulk_review)) engine$write_manifest(spec$bulk_review, file.path(output, "bulk_review.json"))
  } else if (spec$tool %in% tb_general_tools) {
    bundle <- tb_with_input(spec$inputs$matrix, tb_prepare_general(spec))
  } else if (spec$tool == "immune") {
    bundle <- tb_immune_bundle(spec, engine, output, root)
  } else if (spec$tool == "circos") {
    bundle <- tb_prepare_circos(spec, output, engine)
  } else if (spec$tool %in% c("matrix_pca", "matrix_heatmap")) {
    bundle <- tb_matrix_bundle(spec, engine)
  } else if (spec$tool == "network" && spec$params$network_mode == "files") {
    bundle <- tb_with_input(c(spec$inputs$nodes, spec$inputs$edges), tb_import_network(spec, output), "BW-I04")
    tb_network_matrices(list(counts = NULL), list(ppi = list(nodes = bundle$data, edges = bundle$extras$edges)), output, engine)
  } else if (spec$tool == "custom_heatmap" && !nzchar(spec$inputs$matrix)) {
    bundle <- tb_legacy_heatmap(spec, NULL, NULL, root, directory, engine)
  } else {
    if (nzchar(spec$inputs$matrix)) {
      cfg <- tb_config(spec, root, directory, engine)
      analysis <- tb_processed_expression(spec, cfg, engine)
      engine$write_table(analysis$samples, file.path(output, "sample_mapping.csv"))
    } else if (nzchar(spec$inputs$deg)) {
      cfg <- tb_config(spec, root, directory, engine, with_samples = FALSE)
      deg <- tb_with_input(spec$inputs$deg, tb_prepare_deg(spec$inputs$deg, ranked = spec$tool == "gsea"))
      analysis <- list(deg = deg, genes = deg[c("gene_id", "gene_name")])
    } else {
      cfg <- tb_config(spec, root, directory, engine)
      analysis <- tb_model(cfg, engine, root, directory)
    }
    tb_status_write(directory, "running", 65, "模型 / 差异数据已就绪，正在准备所选工具。")
    if (!is.null(analysis$deg) && all(c("padj", "log2FoldChange") %in% names(analysis$deg)) &&
        spec$params$group_mode != "joint") tb_selection_output(analysis, cfg, directory, engine)
    if (spec$tool == "deg") {
      vst <- analysis$vst
      engine$write_table(data.frame(gene_id = rownames(vst), vst, check.names = FALSE), file.path(output, "vst.csv"))
    }
    if (spec$tool == "custom_heatmap") {
      cfg$selection$heatmap_mode <- "custom"
      cfg$selection$target_genes <- spec$inputs$targets
      bundle <- engine$prepare_heatmap(analysis, cfg$selection)
      if (!spec$params$row_scale) bundle$extras$matrix_units <- "Expression"
    } else if (spec$tool == "manual_heatmap") {
      bundle <- tb_legacy_heatmap(spec, cfg, analysis, root, directory, engine)
    } else if (spec$tool != "deg") {
      type <- switch(spec$tool, pca = "pca", volcano = "volcano", heatmap = "heatmap",
                       go = "enrichment", kegg = "enrichment", gsea = "gsea", gsva = "gsva", network = "network")
      pathways <- NULL
      if (spec$tool %in% c("go", "kegg", "gsea", "gsva", "network")) {
        if (spec$tool %in% tb_pathway_tools && spec$params$pathway_source != "custom") {
          cfg <- tryCatch(tb_public_pathways(cfg, spec, analysis$genes, root, directory, engine), error = function(e) {
            if (inherits(e, "bioworkbench_error")) stop(e)
            tb_fail("BW-D01", conditionMessage(e), hint = "请检查物种、基因 ID 和公共库连接，或改用本地 GMT。", parent = e)
          })
        }
        if (spec$tool == "network" && isTRUE(spec$params$ppi_reference) && !nzchar(spec$inputs$edges)) {
          cfg$pathways$ppi_edges <- tryCatch(tb_string_edges(analysis, cfg, spec, root, output, engine), error = function(e) {
            if (inherits(e, "bioworkbench_error")) stop(e)
            tb_fail("BW-D01", conditionMessage(e), hint = "请检查本机对应物种的 STRING 参考库，或上传互作 Edge 表。", parent = e)
          })
          cfg$pathways$ppi_score_scale <- "unit"
        }
        cfg$pathways$enabled <- switch(spec$tool, go = "ora", kegg = "ora", gsea = "gsea", gsva = "gsva", network = "ppi")
        pathways <- if (type == "network" && nzchar(spec$inputs$edges)) {
          tb_with_input(spec$inputs$edges, engine$analyze_pathways(analysis, cfg, output))
        } else engine$analyze_pathways(analysis, cfg, output)
        engine$write_manifest(cfg$pathways, file.path(output, "annotation_source.json"))
        saveRDS(pathways, file.path(output, "pathways.rds"))
        tables_only <- type == "network" && isTRUE(spec$params$ppi_tables_only)
        if (type == "network" && !tables_only) tb_network_matrices(analysis, pathways, output, engine)
        table <- if (type == "enrichment") pathways$ora$results else if (type == "gsea") pathways$gsea$results else NULL
        empty <- (!is.null(table) && !nrow(table)) ||
          (type == "enrichment" && !any(is.finite(table$p.adjust) & table$p.adjust <= cfg$pathways$ora_padj)) ||
          (type == "gsva" && !nrow(pathways$gsva$results)) ||
          (type == "network" && !nrow(pathways$ppi$nodes))
        if (empty) {
          engine$write_manifest(list(status = "completed", note = "无符合当前条件的条目；已保存完整结果表。"), file.path(output, "result_note.json"))
        } else if (!tables_only) bundle <- engine$prepare_bundle(analysis, cfg, type, pathways)
      } else bundle <- engine$prepare_bundle(analysis, cfg, type)
    }
  }
  if (!is.null(bundle)) {
    if (bundle$type == "network") bundle$extras$topology <- tb_prepare_ppi_topology(bundle, root)
    if (bundle$type == "heatmap" && nzchar(spec$inputs$matrix) && bundle$extras$matrix_units %in% "VST")
      bundle$extras$matrix_units <- "Expression"
    bundle$provenance <- list(tool = spec$tool, parameters = spec$params)
    saveRDS(bundle, file.path(directory, "render.rds"))
    tb_render_request(bundle, spec, root, directory, engine)
  }
  engine$write_manifest(list(tool = spec$tool, parameters = spec$params, style = spec$style,
                              input_sha256 = engine$file_fingerprint(unlist(spec$inputs[file.exists(unlist(spec$inputs))])),
                              R = as.character(getRversion()),
                              packages = engine$package_versions(c("DESeq2", "ggplot2", "ComplexHeatmap", "circlize"))),
                         file.path(output, "manifest.json"))
  if (!is.null(cfg)) dput(cfg, file = file.path(output, "config_resolved.R"))
  writeLines(capture.output(utils::sessionInfo()), file.path(output, "sessionInfo.txt"))
  message("结果目录：", output)
  summary <- if (file.exists(file.path(output, "result_note.json"))) {
    "分析完成，当前条件无可绘图条目；完整结果表已保存。"
  } else if (spec$tool == "network" && isTRUE(spec$params$ppi_tables_only)) {
    "PPI 数据准备完成，节点表和边表已保存。"
  } else if (spec$tool == "deg") "差异分析完成，完整结果与筛选表已保存。" else {
    "所选工具已完成；结果表、参数与图形已保存。"
  }
  tb_status_write(directory, "completed", 100, summary)
  invisible(output)
}
