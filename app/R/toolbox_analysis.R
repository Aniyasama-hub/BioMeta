# 计算层仅由独立 worker 调用；重用项目模块，不在界面线程执行分析。
tb_engine <- function(root) {
  environment <- new.env(parent = globalenv())
  for (file in c("core.R", "analysis.R", "prepare.R", "pathways.R", "plots.R")) {
    sys.source(file.path(root, "R", file), envir = environment)
  }
  environment
}

tb_samples <- function(path, parameters) {
  samples <- tb_read_preview(path, n = -1)
  if (all(c("Sample", "Group") %in% names(samples))) {
    samples$source_sample_id <- trimws(as.character(samples$Sample))
    samples$condition <- trimws(as.character(samples$Group))
    samples$sample_id <- gsub("[^A-Za-z0-9_.-]", "_", samples$source_sample_id)
    samples$sample_id <- ifelse(grepl("^[A-Za-z0-9]", samples$sample_id),
                                 samples$sample_id, paste0("S", samples$sample_id))
  }
  if (!all(c("sample_id", "condition") %in% names(samples))) {
    stop("分组表需含 Sample,Group，或 sample_id,condition。")
  }
  if (!"source_sample_id" %in% names(samples)) samples$source_sample_id <- samples$sample_id
  if (anyDuplicated(samples$sample_id)) stop("安全样本 ID 重名，请在分组表显式提供唯一 sample_id 和 source_sample_id。")
  if (!"batch" %in% names(samples)) samples$batch <- "single_batch"
  if (!"include" %in% names(samples)) samples$include <- TRUE
  include <- toupper(as.character(samples$include))
  if (anyNA(include) || any(!include %in% c("TRUE", "FALSE"))) stop("include 只能为 TRUE/FALSE。")
  samples <- samples[include == "TRUE", , drop = FALSE]
  samples <- samples[as.character(samples$condition) %in% c(parameters$control, parameters$treatment), , drop = FALSE]
  if (!nrow(samples)) stop("比较组未匹配分组表；请保留 HA@CuPB 等原始组名。")
  samples
}

tb_config <- function(spec, root, directory, engine) {
  cfg <- engine$load_config(file.path(root, "config", "project.R"))
  p <- spec$params
  samples <- tb_samples(spec$inputs$groups, p)
  sample_path <- file.path(directory, "inputs", "sample_mapping.csv")
  engine$write_table(samples, sample_path)
  cfg$input$mode <- "counts"
  cfg$input$counts <- spec$inputs$counts
  cfg$input$samples <- sample_path
  cfg$input$genes <- NULL
  cfg$project$output <- file.path(directory, "outputs")
  cfg$analysis$condition_levels <- c(p$control, p$treatment)
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
  cfg$selection$distance <- p$distance
  cfg$selection$linkage <- p$linkage
  cfg$selection$pathway_top_n <- as.integer(p$pathway_top)
  cfg$selection$pathway_id <- if (nzchar(p$pathway_id)) p$pathway_id else NULL
  cfg$selection$label_top_n <- if (isTRUE(p$labels)) 8L else 0L
  cfg$pathways$min_size <- as.integer(p$min_set_size)
  cfg$pathways$max_size <- as.integer(p$max_set_size)
  cfg$pathways$gmt_id_type <- p$gmt_id_type
  cfg$pathways$gmt <- if (nzchar(spec$inputs$gmt)) spec$inputs$gmt else NULL
  cfg$pathways$database_label <- if (spec$tool == "go") paste0("GO_", p$go_ontology) else if (spec$tool == "kegg") "KEGG" else "user_GMT"
  cfg$pathways$database_version <- p$database_version
  cfg$pathways$ora_padj <- p$padj
  cfg$pathways$gsea_padj <- p$padj
  cfg$pathways$ppi_edges <- spec$inputs$edges
  cfg$pathways$ppi_score <- p$ppi_score
  cfg$style <- utils::modifyList(cfg$style, spec$style)
  cfg$style$colors <- c(Up = spec$style$up, Down = spec$style$down,
                         Not_significant = spec$style$neutral)
  cfg$style$show_sample_labels <- isTRUE(p$labels)
  cfg$style$group_colors <- stats::setNames(c(spec$style$down, spec$style$up), c(p$control, p$treatment))
  cfg$style$formats <- spec$style$formats
  cfg
}

tb_model <- function(cfg, engine, root, directory) {
  engine$require_packages(c("DESeq2", "SummarizedExperiment", "digest", "jsonlite"))
  samples <- engine$read_samples(cfg)
  engine$make_design(samples, cfg)
  fingerprint <- list(counts = digest::digest(file = cfg$input$counts, algo = "sha256"),
                       samples = samples, analysis = cfg$analysis, contrast = cfg$contrast,
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

tb_local_go <- function(cfg, directory, engine) {
  engine$require_packages(c("org.Mm.eg.db", "GO.db", "AnnotationDbi"))
  ontology <- sub("^GO_", "", cfg$pathways$database_label)
  if (!ontology %in% c("BP", "CC", "MF", "ALL")) stop("GO ontology 只支持 BP/CC/MF/ALL。")
  db <- getExportedValue("org.Mm.eg.db", "org.Mm.eg.db")
  # GOALL 为继承祖先关系的注释；以 SYMBOL 记录并交由公共 ID 映射层处理。
  map <- AnnotationDbi::select(db, keys = AnnotationDbi::keys(db, keytype = "SYMBOL"),
                                keytype = "SYMBOL", columns = c("GOALL", "ONTOLOGYALL"))
  map <- unique(map[!is.na(map$GOALL) & !is.na(map$SYMBOL), ])
  if (ontology != "ALL") map <- map[map$ONTOLOGYALL == ontology, ]
  terms <- AnnotationDbi::select(getExportedValue("GO.db", "GO.db"),
                                  keys = unique(map$GOALL), keytype = "GOID", columns = "TERM")
  sets <- split(map$SYMBOL, map$GOALL)
  gmt <- file.path(directory, "outputs", "GO_annotation.gmt")
  writeLines(vapply(names(sets), function(id) {
    description <- terms$TERM[match(id, terms$GOID)]
    paste(c(id, ifelse(is.na(description), id, description), unique(sets[[id]])), collapse = "\t")
  }, character(1)), gmt, useBytes = TRUE)
  cfg$pathways$gmt <- gmt
  cfg$pathways$gmt_id_type <- "SYMBOL"
  cfg$pathways$database_version <- paste0("org.Mm.eg.db ", utils::packageVersion("org.Mm.eg.db"),
                                          "; GO.db ", utils::packageVersion("GO.db"))
  cfg
}

tb_prepare_deg <- function(path, cfg) {
  data <- tb_read_preview(path, n = -1)
  if (!"log2FoldChange" %in% names(data) && "log2FC" %in% names(data)) data$log2FoldChange <- data$log2FC
  if (!"gene_id" %in% names(data)) stop("差异表缺少 gene_id。")
  if (anyNA(data$gene_id) || any(!nzchar(trimws(data$gene_id))) || anyDuplicated(data$gene_id)) {
    stop("差异表 gene_id 必须非空且唯一。")
  }
  if (!"gene_name" %in% names(data)) data$gene_name <- data$gene_id
  if (!all(c("log2FoldChange", "padj") %in% names(data))) stop("差异表需含 log2FC/log2FoldChange 和 padj。")
  for (column in c("log2FoldChange", "padj")) {
    converted <- suppressWarnings(as.numeric(data[[column]]))
    bad <- is.na(converted) & !is.na(data[[column]]) & nzchar(as.character(data[[column]]))
    if (any(bad)) stop("差异表数值列含非数值：", column)
    data[[column]] <- converted
    if (any(is.infinite(converted))) stop("差异表数值不能为 Inf：", column)
  }
  if (any(is.finite(data$padj) & (data$padj < 0 | data$padj > 1))) stop("padj 必须位于 [0,1] 或为 NA。")
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
  for (expression in expressions) {
    assignment <- is.call(expression) && identical(expression[[1]], as.name("<-")) && is.symbol(expression[[2]])
    name <- if (assignment) as.character(expression[[2]]) else ""
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
  invisible(NULL)
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

tb_open_device <- function(path, format, width, height, dpi, background = "white") {
  if (format == "png") grDevices::png(path, width = width, height = height, units = "in", res = dpi, bg = background)
  else if (format == "svg") svglite::svglite(path, width = width, height = height, bg = background)
  else if (format == "tiff") grDevices::tiff(path, width = width, height = height, units = "in", res = dpi, compression = "lzw", bg = background)
  else if (format == "pdf") grDevices::pdf(path, width = width, height = height, bg = background)
  else stop("未知图像格式：", format)
}

tb_legacy_heatmap <- function(spec, cfg, analysis, root, directory, engine) {
  output <- file.path(directory, "outputs")
  samples <- tb_samples(spec$inputs$groups, spec$params)
  metadata <- data.frame(Sample = samples$source_sample_id, Group = samples$condition)
  group_path <- file.path(directory, "inputs", "legacy_groups.csv")
  engine$write_table(metadata, group_path)
  style <- spec$style
  overrides <- list(work_dir = dirname(root), output_dir = output,
                    group_file = group_path, metadata_file = group_path,
                    selected_groups = c(spec$params$control, spec$params$treatment),
                    output_formats = style$formats,
                    image_width = style$width, image_height = style$height,
                    figure_width = style$width, figure_height = style$height,
                    dpi = style$dpi, heatmap_colors = c(style$low, style$mid, style$high),
                    scale_limit = style$z_limit, cluster_rows = spec$params$cluster_rows,
                    cluster_columns = spec$params$cluster_columns,
                    heatmap_scale = if (spec$params$row_scale) "row" else "none",
                    show_sample_names = spec$params$labels, show_column_names = spec$params$labels,
                    cluster_within_process = spec$params$cluster_rows,
                    pseudo_count = spec$params$log_pseudocount,
                    min_total_count = spec$params$min_count, export_legend_position = style$legend_position, export_background = style$background,
                    font_family = style$font_family, gene_font_size = style$row_font_size,
                    row_names_fontsize = style$row_font_size, sample_font_size = style$column_font_size,
                    column_font_size = style$column_font_size, sample_name_rotation = style$column_rotation,
                    column_name_rotation = style$column_rotation, gene_font_color = if (style$show_gene_names) "#222222" else "transparent",
                    show_gene_names = style$show_gene_names, na_color = style$na_color,
                    cell_border_color = style$cell_border, cell_border_width = style$cell_border_width,
                    use_raster = style$heatmap_raster, use_raster_heatmap = style$heatmap_raster)
  if (spec$tool == "custom_heatmap") {
    targets <- tb_read_preview(spec$inputs$targets, n = -1)
    column <- intersect(c("GeneKey", "gene_name", "GeneSymbol", names(targets)[1]), names(targets))[1]
    if ("Use" %in% names(targets)) targets <- targets[toupper(targets$Use) != "FALSE", , drop = FALSE]
    overrides$count_file <- spec$inputs$counts
    overrides$target_genes <- unique(trimws(as.character(targets[[column]])))
    overrides$normalization_method <- spec$params$custom_transform
    overrides$draw_one <- function(fmt) {
      path <- file.path(out_path, paste0(output_prefix, "_Heatmap.", fmt))
      tb_open_device(path, fmt, image_width, image_height, dpi, export_background)
      on.exit(grDevices::dev.off(), add = TRUE)
      ComplexHeatmap::draw(ht, column_title = plot_title,
        column_title_gp = grid::gpar(fontfamily = font_family, fontsize = title_font_size,
          fontface = title_font_face, col = title_font_color), heatmap_legend_side = export_legend_position, background = export_background)
    }
    script <- "04.4_custom_gene_count_heatmap.R"
  } else {
    deg <- analysis$deg
    raw <- analysis$counts[deg$gene_id, , drop = FALSE]
    source_names <- analysis$samples$source_sample_id[match(colnames(raw), analysis$samples$sample_id)]
    colnames(raw) <- source_names
    deg$log2FC <- deg$log2FoldChange
    table <- cbind(deg, as.data.frame(raw, check.names = FALSE))
    expression_path <- file.path(directory, "inputs", "manual_expression.csv")
    engine$write_table(table, expression_path)
    overrides$expression_file <- expression_path
    overrides$manual_annotation_file <- spec$inputs$annotation
    overrides$padj_cutoff <- spec$params$padj
    overrides$log2fc_cutoff <- spec$params$log2fc
    overrides$top_n_genes <- as.integer(spec$params$heatmap_top)
    overrides$draw_file <- function(fmt) {
      path <- file.path(output_dir, paste0(project_name, "_Heatmap.", fmt))
      tb_open_device(path, fmt, image_width, image_height, dpi, export_background)
      on.exit(grDevices::dev.off(), add = TRUE)
      ComplexHeatmap::draw(ht, heatmap_legend_side = export_legend_position, align_heatmap_legend = "global_center", background = export_background)
    }
    script <- "04.3_manual_pathway_heatmap.R"
  }
  engine$require_packages(c("ComplexHeatmap", "circlize", "svglite"))
  source <- file.path(dirname(root), "legacy", script)
  # 当前脚本身份写入结果，便于区分后续用户修改版本。
  engine$write_manifest(list(source = source, sha256 = digest::digest(file = source, algo = "sha256"),
                              overrides = overrides[!vapply(overrides, is.function, logical(1))]), file.path(output, "source_adapter.json"))
  tb_run_legacy(source, overrides, normalize_counts = spec$tool == "custom_heatmap")
}

tb_read_matrix <- function(path, parameters) {
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
}

tb_matrix_bundle <- function(spec, engine) {
  matrix <- tb_read_matrix(spec$inputs$matrix, spec$params)
  metadata <- data.frame(sample_id = colnames(matrix), condition = "Samples", batch = "not_applicable",
                         row.names = colnames(matrix))
  if (isTRUE(spec$params$matrix_use_groups) && nzchar(spec$inputs$groups)) {
    groups <- tb_read_preview(spec$inputs$groups, n = -1)
    id_column <- intersect(c("Sample", "source_sample_id", "sample_id"), names(groups))[1]
    group_column <- intersect(c("Group", "condition"), names(groups))[1]
    if (is.na(id_column) || is.na(group_column)) stop("分组表需含 Sample/Group 或 sample_id/condition。")
    if (anyDuplicated(groups[[id_column]]) || !all(colnames(matrix) %in% groups[[id_column]])) stop("分组表必须唯一覆盖全部矩阵样本。")
    metadata$condition <- groups[[group_column]][match(colnames(matrix), groups[[id_column]])]
  }
  genes <- data.frame(gene_id = rownames(matrix), gene_name = rownames(matrix), row.names = rownames(matrix))
  analysis <- list(vst = matrix, genes = genes, samples = metadata)
  selection <- list(use_batch_visualization = FALSE, pca_top_genes = nrow(matrix),
                      pca_scale = spec$params$pca_scale, heatmap_mode = "variable",
                      heatmap_top_n = min(nrow(matrix), spec$params$heatmap_top), row_zscore = spec$params$row_scale,
                      cluster_rows = spec$params$cluster_rows, cluster_columns = spec$params$cluster_columns,
                      distance = spec$params$distance, linkage = spec$params$linkage)
  bundle <- engine$prepare_bundle(analysis, list(selection = selection),
                                   if (spec$tool == "matrix_pca") "pca" else "heatmap")
  if (spec$tool == "matrix_heatmap") {
    bundle$extras$matrix_units <- if (spec$params$row_scale) "row_zscore" else spec$params$matrix_transform
  }
  bundle
}

tb_save_circos <- function(spec, output, engine) {
  engine$require_packages(c("circlize", "svglite"))
  chromosomes <- tb_read_preview(spec$inputs$chromosomes, n = -1)
  if (!all(c("chr", "length") %in% names(chromosomes))) stop("染色体 CSV/TSV 需含表头 chr,length。")
  if (anyDuplicated(chromosomes$chr) || any(!nzchar(chromosomes$chr)) ||
      any(!is.finite(chromosomes$length)) || any(chromosomes$length <= 0)) stop("染色体名称必须唯一，长度必须为正数。")
  regions <- function(path, required) {
    if (!nzchar(path)) return(NULL)
    data <- tb_read_preview(path, n = -1)
    if (!all(required %in% names(data))) stop("区域文件缺少列：", paste(required, collapse = ", "))
    data
  }
  features <- regions(spec$inputs$features, c("chr", "start", "end", "label"))
  links <- regions(spec$inputs$links, c("chr1", "start1", "end1", "chr2", "start2", "end2"))
  check_regions <- function(chr, start, end) {
    max_length <- chromosomes$length[match(chr, chromosomes$chr)]
    if (anyNA(max_length) || any(!is.finite(start)) || any(!is.finite(end)) ||
        any(start < 0 | end <= start | end > max_length)) stop("区域须匹配染色体，且满足 0 <= start < end <= length。")
  }
  if (!is.null(features)) check_regions(features$chr, features$start, features$end)
  if (!is.null(links)) {
    check_regions(links$chr1, links$start1, links$end1)
    check_regions(links$chr2, links$start2, links$end2)
  }
  engine$write_table(chromosomes, file.path(output, "plot_data.csv"))
  if (!is.null(features)) engine$write_table(features, file.path(output, "features.csv"))
  if (!is.null(links)) engine$write_table(links, file.path(output, "links.csv"))
  draw <- function() {
    on.exit(circlize::circos.clear(), add = TRUE)
    circlize::circos.par(start.degree = spec$style$start_degree, gap.degree = spec$style$gap_degree)
    circlize::circos.initialize(chromosomes$chr, xlim = cbind(0, chromosomes$length))
    circlize::circos.trackPlotRegion(ylim = c(0, 1), bg.col = rep(spec$style$chromosome_color, nrow(chromosomes)),
      track.height = spec$style$track_height, panel.fun = function(x, y) {
        chr <- circlize::get.cell.meta.data("sector.index")
        center <- circlize::get.cell.meta.data("xcenter")
        circlize::circos.text(center, 0.5, chr, col = "white", cex = spec$style$circos_label_size,
                               facing = "bending.inside", niceFacing = TRUE)
        circlize::circos.axis(labels.cex = 0.5)
      })
    if (!is.null(features)) {
      circlize::circos.genomicTrackPlotRegion(features[, c("chr", "start", "end", "label")], ylim = c(0, 1),
        track.height = 0.12, bg.border = NA, panel.fun = function(region, value, ...) {
          circlize::circos.genomicRect(region, ybottom = 0.2, ytop = 0.5, col = spec$style$feature_color, border = NA)
          circlize::circos.genomicText(region, value, y = 0.8, labels.column = 1, cex = spec$style$circos_label_size, niceFacing = TRUE)
        })
    }
    if (!is.null(links)) for (i in seq_len(nrow(links))) {
      circlize::circos.link(links$chr1[i], c(links$start1[i], links$end1[i]),
                             links$chr2[i], c(links$start2[i], links$end2[i]),
                             col = grDevices::adjustcolor(spec$style$link_color, alpha.f = spec$style$link_alpha), border = NA)
    }
  }
  for (format in spec$style$formats) {
    path <- file.path(output, paste0("figure.", format))
    style <- spec$style
    if (format == "png") grDevices::png(path, width = style$width, height = style$height, units = "in", res = style$dpi, bg = style$background)
    if (format == "svg") svglite::svglite(path, width = style$width, height = style$height, bg = style$background)
    if (format == "tiff") grDevices::tiff(path, width = style$width, height = style$height, units = "in", res = style$dpi, compression = "lzw", bg = style$background)
    if (format == "pdf") grDevices::pdf(path, width = style$width, height = style$height, bg = style$background)
    graphics::par(family = style$font_family, cex = style$base_size / 12)
    tryCatch(draw(), finally = grDevices::dev.off())
  }
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

tb_pca_supplement <- function(bundle, spec, output, engine, style) {
  # 同一 PCA 结果派生负荷图和 3D 图，不重新拟合；只有存在 PC3 时输出三维视图。
  loadings <- as.data.frame(bundle$extras$pca$rotation)
  loadings$gene_id <- rownames(loadings)
  loadings$contribution <- loadings$PC1^2 + loadings$PC2^2
  loadings <- loadings[order(loadings$contribution, decreasing = TRUE), , drop = FALSE]
  engine$write_table(loadings, file.path(output, "loading_plot_data.csv"))
  plot <- ggplot2::ggplot(loadings, ggplot2::aes(PC1, PC2)) +
    ggplot2::geom_hline(yintercept = 0, color = "grey85") +
    ggplot2::geom_vline(xintercept = 0, color = "grey85") +
    ggplot2::geom_point(color = style$group_a, alpha = style$point_alpha, size = style$point_size, shape = as.integer(style$point_shape)) +
    ggplot2::labs(x = "PC1 loading", y = "PC2 loading") +
    engine$.plot_theme(style)
  if (spec$params$labels) plot <- plot + ggrepel::geom_text_repel(
    data = head(loadings, 20), ggplot2::aes(label = gene_id), size = style$label_size, seed = 1)
  engine$.save_ggplot_bundle(plot, file.path(output, "pca_loadings"), style)
  if (!"PC3" %in% names(bundle$data)) return(invisible(NULL))
  engine$require_packages("scatterplot3d")
  data <- bundle$data
  groups <- factor(data$condition)
  colors <- engine$.group_palette(levels(groups), style$group_colors, style$palette)
  directory <- file.path(output, "pca_3d")
  dir.create(directory, showWarnings = FALSE)
  for (format in style$formats) {
    tb_open_device(file.path(directory, paste0("figure.", format)), format,
                     style$width, style$height, style$dpi, style$background)
    tryCatch({
      scatterplot3d::scatterplot3d(data$PC1, data$PC2, data$PC3, color = colors[as.character(groups)],
        pch = as.integer(style$point_shape), cex.symbols = style$point_size / 2,
        angle = style$pca_3d_angle, xlab = sprintf("PC1 (%.1f%%)", bundle$extras$variance[1]),
        ylab = sprintf("PC2 (%.1f%%)", bundle$extras$variance[2]),
        zlab = sprintf("PC3 (%.1f%%)", bundle$extras$variance[3]))
      graphics::legend("topright", levels(groups), col = colors, pch = 19, bty = "n")
    }, finally = grDevices::dev.off())
  }
  invisible(NULL)
}

tb_run_request <- function(spec, root, directory) {
  spec <- tb_normalize_spec(spec, root)
  tb_validate_inputs(spec, root)
  engine <- tb_engine(root)
  engine$require_packages(c("jsonlite", "digest"))
  output <- file.path(directory, "outputs")
  dir.create(output, showWarnings = FALSE)
  tb_status_write(directory, "running", 10, "读取参数与输入快照。")
  tb_write_reproduce(spec, file.path(directory, "reproduce.R"), root)
  bundle <- NULL
  cfg <- NULL
  if (spec$tool == "circos") {
    tb_save_circos(spec, output, engine)
  } else if (spec$tool %in% c("matrix_pca", "matrix_heatmap")) {
    bundle <- tb_matrix_bundle(spec, engine)
  } else if (spec$tool == "network" && spec$params$network_mode == "files") {
    bundle <- tb_import_network(spec, output)
    tb_network_matrices(list(counts = NULL), list(ppi = list(nodes = bundle$data, edges = bundle$extras$edges)), output, engine)
  } else if (spec$tool == "custom_heatmap") {
    tb_legacy_heatmap(spec, NULL, NULL, root, directory, engine)
  } else {
    if (spec$tool == "volcano" && nzchar(spec$inputs$deg)) {
      # 直接读取已完成的差异表，不因调配色重复拟合 DESeq2。
      template <- new.env(parent = baseenv())
      sys.source(file.path(root, "config", "project.R"), template)
      cfg <- template$config
      cfg$contrast <- list(numerator = spec$params$treatment, denominator = spec$params$control)
      cfg$selection$padj_cutoff <- spec$params$padj
      cfg$selection$log2fc_cutoff <- spec$params$log2fc
      cfg$selection$direction <- spec$params$direction
      cfg$selection$label_top_n <- if (spec$params$labels) 8L else 0L
      analysis <- list(deg = tb_prepare_deg(spec$inputs$deg, cfg))
    } else {
      cfg <- tb_config(spec, root, directory, engine)
      analysis <- tb_model(cfg, engine, root, directory)
    }
    tb_status_write(directory, "running", 65, "模型 / 差异数据已就绪，正在准备所选工具。")
    tb_selection_output(analysis, cfg, directory, engine)
    if (spec$tool == "manual_heatmap") {
      tb_legacy_heatmap(spec, cfg, analysis, root, directory, engine)
    } else if (spec$tool != "deg") {
      type <- switch(spec$tool, pca = "pca", volcano = "volcano", heatmap = "heatmap",
                       go = "enrichment", kegg = "enrichment", gsea = "gsea", gsva = "gsva", network = "network")
      pathways <- NULL
      if (spec$tool %in% c("go", "kegg", "gsea", "gsva", "network")) {
        if (spec$tool == "go" && is.null(cfg$pathways$gmt)) cfg <- tb_local_go(cfg, directory, engine)
        cfg$pathways$enabled <- switch(spec$tool, go = "ora", kegg = "ora", gsea = "gsea", gsva = "gsva", network = "ppi")
        pathways <- engine$analyze_pathways(analysis, cfg, output)
        engine$write_manifest(cfg$pathways, file.path(output, "annotation_source.json"))
        saveRDS(pathways, file.path(output, "pathways.rds"))
        if (spec$tool == "network") tb_network_matrices(analysis, pathways, output, engine)
        table <- if (type == "enrichment") pathways$ora$results else if (type == "gsea") pathways$gsea$results else NULL
        empty <- (!is.null(table) && !nrow(table)) ||
          (type == "enrichment" && !any(is.finite(table$p.adjust) & table$p.adjust < cfg$pathways$ora_padj)) ||
          (type == "gsva" && !nrow(pathways$gsva$results)) ||
          (type == "network" && !nrow(pathways$ppi$nodes))
        if (empty) {
          engine$write_manifest(list(status = "completed", note = "无符合当前条件的条目；已保存完整结果表。"), file.path(output, "result_note.json"))
        } else bundle <- engine$prepare_bundle(analysis, cfg, type, pathways)
      } else bundle <- engine$prepare_bundle(analysis, cfg, type)
    }
  }
  if (!is.null(bundle)) {
    tb_status_write(directory, "running", 85, "准备绘图数据与多格式导出。")
    engine$require_packages(c("ggplot2", "ggrepel", "svglite"))
    if (bundle$type == "heatmap") engine$require_packages(c("ComplexHeatmap", "circlize"))
    if (bundle$type == "gsea") engine$require_packages("patchwork")
    style <- utils::modifyList(if (is.null(cfg)) engine$.default_plot_style() else cfg$style, spec$style)
    style$colors <- c(Up = spec$style$up, Down = spec$style$down, Not_significant = spec$style$neutral)
    style$show_sample_labels <- spec$params$labels
    if (bundle$type == "pca") style$palette <- c(spec$style$group_a, spec$style$group_b, "#A89046", "#697C61")
    if (bundle$type == "pca") style$group_colors <- NULL
    style$formats <- spec$style$formats
    bundle$provenance <- list(tool = spec$tool, parameters = spec$params, source = "local_R_toolbox")
    engine$export_bundle(bundle, output)
    engine$render_bundle(bundle, style, output)
    if (bundle$type == "network") tb_write_interactive_network(bundle, style, root, output)
    if (bundle$type == "pca") tb_pca_supplement(bundle, spec, output, engine, style)
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
  } else if (spec$tool == "deg") "差异分析完成，完整结果与筛选表已保存。" else {
    "所选工具已完成；结果表、参数与图形已保存。"
  }
  tb_status_write(directory, "completed", 100, summary)
  invisible(output)
}
