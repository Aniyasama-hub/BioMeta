# Shared by validation, ORA, plotting preparation and portable R exports.
tb_metric_aliases <- list(
  probability = c("padj", "p.adjust", "adj.P.Val", "p_val_adj", "FDR", "fdr", "qvalue", "q_value", "pvalue", "pval", "P.Value", "p_value", "p_val"),
  effect = c("log2FoldChange", "log2FC", "logFC", "avg_log2FC", "log2fc", "logfc"))

tb_pathway_key <- function(x) {
  values <- gsub("(?i)\\[(?:BP|CC|MF|GO|KEGG|REACTOME|RECATOME)\\]", "", x, perl = TRUE)
  values <- sub(" - (Homo sapiens|Mus musculus) \\([^)]*\\)$", "", trimws(values), ignore.case = TRUE)
  values <- sub("^path:", "", values, ignore.case = TRUE)
  tolower(trimws(gsub("[[:space:]]+", " ", values)))
}

# A lookup never starts a download in the interface thread.
tb_library_catalog <- function(root, source, species) {
  if (source == "go") {
    if (!requireNamespace("GO.db", quietly = TRUE) || !requireNamespace("AnnotationDbi", quietly = TRUE))
      stop("名称查询需要 GO.db 和 AnnotationDbi，请先在设置中检查。")
    db <- getExportedValue("GO.db", "GO.db")
    ids <- AnnotationDbi::keys(db, keytype = "GOID")
    labels <- suppressMessages(AnnotationDbi::mapIds(db, ids, "TERM", "GOID", multiVals = "asNA"))
    table <- data.frame(term = ids, label = unname(labels[ids]))
  } else {
    if (!source %in% c("kegg", "reactome")) stop("本地 GMT 请使用文件中的正式名称或编号。")
    organism <- if (species == "human") "hsa" else "mmu"
    path <- file.path(root, "results", "toolbox", "references", paste0(source, "-", organism, ".rds"))
    if (!file.exists(path)) stop("该物种尚无本地注释缓存。可先直接输入官网编号，或运行一次对应公共库分析后再查询名称。")
    table <- readRDS(path)$table[c("term", "label")]
  }
  unique(table[!is.na(table$term) & !is.na(table$label) & nzchar(table$label), ])
}

tb_metric_column <- function(data, chosen, kind) {
  if (nzchar(chosen %||% "")) {
    if (!chosen %in% names(data)) stop("所选指标列不存在：", chosen)
    return(chosen)
  }
  found <- intersect(tb_metric_aliases[[kind]], names(data))
  if (length(found)) found[1L] else ""
}

tb_metric_values <- function(data, column, probability = FALSE) {
  raw <- data[[column]]
  values <- suppressWarnings(as.numeric(raw))
  bad <- is.na(values) & !is.na(raw) & nzchar(trimws(as.character(raw)))
  if (any(bad) || any(is.infinite(values))) stop("指标列含非数值或无穷值：", column)
  if (probability && any(values < 0 | values > 1, na.rm = TRUE))
    stop("显著性列应为 0–1 的概率，不能使用负对数值：", column)
  values
}

tb_ora_selection <- function(data, selection) {
  probability <- tb_metric_column(data, selection$ora_p_column, "probability")
  effect <- tb_metric_column(data, selection$ora_effect_column, "effect")
  mode <- selection$ora_filter_mode %||% "auto"
  if (mode == "auto") mode <- if (nzchar(probability) && nzchar(effect)) "both"
    else if (nzchar(probability)) "probability" else "effect"
  if (!mode %in% c("both", "probability", "effect")) stop("请选择有效的候选基因筛选方式。")
  use_p <- mode %in% c("both", "probability")
  use_effect <- mode %in% c("both", "effect")
  direction <- selection$direction %||% "all"
  if (!direction %in% c("all", "up", "down")) stop("请选择候选基因方向。")
  if (use_p && !nzchar(probability)) stop("没有识别到显著性列，请选择实际 P value、Adjusted P value 或 FDR 列。")
  if ((use_effect || direction != "all") && !nzchar(effect))
    stop("按变化幅度或上/下调筛选需要实际 logFC 列；也可以改为仅显著性、方向全部。")
  threshold <- selection$padj_cutoff %||% selection$padj %||% .05
  magnitude <- selection$log2fc_cutoff %||% selection$log2fc %||% 1
  raw_p <- if (use_p) intersect(c("pvalue", "pval", "P.Value", "p_value", "p_val"), names(data)) else character()
  background_column <- if (length(raw_p)) raw_p[1L] else if (use_p) probability else effect
  tested <- is.finite(tb_metric_values(data, background_column, length(raw_p) > 0L || use_p))
  selected <- rep(TRUE, nrow(data))
  if (use_p) {
    values <- tb_metric_values(data, probability, TRUE)
    selected <- selected & is.finite(values) & values <= threshold
  }
  if (use_effect || direction != "all") {
    values <- tb_metric_values(data, effect)
    if (use_effect) selected <- selected & is.finite(values) & abs(values) >= magnitude
    if (direction == "up") selected <- selected & is.finite(values) & values > 0
    if (direction == "down") selected <- selected & is.finite(values) & values < 0
  }
  list(tested = tested, selected = selected & tested,
    specification = list(mode = mode, background_column = background_column,
      background_policy = "finite_raw_pvalue_else_selected_probability_or_effect",
      probability_column = if (use_p) probability else NULL,
      probability_threshold = if (use_p) threshold else NULL,
      effect_column = if (use_effect || direction != "all") effect else NULL,
      absolute_effect_threshold = if (use_effect) magnitude else NULL, direction = direction))
}

tb_pathway_metric <- function(table, metric = "padj") {
  aliases <- switch(metric,
    pvalue = c("pvalue", "pval", "P.Value"), pval = c("pval", "pvalue", "P.Value"),
    padj = c("p.adjust", "padj", "adj.P.Val"), FDR = c("p.adjust", "padj", "adj.P.Val"),
    gene_ratio = c("gene_ratio"), count = c("Count", "count"),
    logFC = c("logFC"), qvalue = "qvalue", stop("未知通路指标：", metric))
  column <- intersect(aliases, names(table))[1L]
  if (is.na(column)) stop("通路结果没有所选指标：", metric)
  values <- as.numeric(table[[column]])
  if (metric == "logFC") values <- abs(values)
  values
}

tb_pathway_input <- function(spec, annotation = FALSE) {
  text <- spec$params[[if (annotation) "annotation_terms" else "target_pathways"]]
  mode <- spec$params[[if (annotation) "annotation_input" else "target_pathway_input"]] %||% "auto"
  if (!mode %in% c("auto", "text", "table")) stop("请选择输入通路名称的方式。")
  tb_read_items(if (mode == "table") "" else text,
    if (mode == "text") "" else spec$inputs$pathway_names, one_row = annotation)
}

tb_bundle_pathways <- function(bundle) {
  if (is.null(bundle)) return(character())
  if (identical(bundle$type, "enrichment_collection"))
    return(unique(unlist(lapply(bundle$plots, tb_bundle_pathways), use.names = FALSE)))
  if (identical(bundle$type, "heatmap")) rownames(bundle$data) else bundle$data$term_id
}
