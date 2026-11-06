tb_species_choices <- c("人" = "human", "小鼠" = "mouse")
tb_pathway_tools <- c("go", "kegg", "gsea", "gsva")
tb_pathway_sources <- function(tool) {
  public <- switch(tool, go = c("Gene Ontology" = "go"),
    kegg = c("KEGG PATHWAY（学术使用）" = "kegg"),
    c("Reactome" = "reactome", "Gene Ontology" = "go", "KEGG PATHWAY（学术使用）" = "kegg"))
  c(public, "上传自建 GMT" = "custom")
}
toolbox_source <- Filter(Negate(is.null), lapply(sys.frames(), function(frame) frame$ofile))
if (length(toolbox_source)) source(file.path(dirname(tail(toolbox_source, 1L)[[1L]]),
  "style_schema.R"), encoding = "UTF-8")
# 本地工具箱公共接口；加载本文件不会拟合模型、联网或生成科研图片。
`%||%` <- function(x, y) if (is.null(x)) y else x
if (!exists(".tb_jobs", inherits = FALSE)) .tb_jobs <- new.env(parent = emptyenv())

tb_general_tools <- c("sankey", "venn", "kmeans", "beeswarm", "radar")
tb_general_titles <- c("桑基图", "韦恩图", "K-means 聚类图", "蜜蜂图", "雷达图")
tb_general_help <- c("输入 source、target、value，展示两阶段流量。", "输入 set、item，统计两个或三个集合的交集。",
  "首列为行标识，以其余数值列聚类，并用 PCA 展示。", "输入 group、value，绘制分组样本分布。",
  "首列为对象标识，其余至少三列为数值指标。")

tb_tool_catalog <- function() {
  tools <- data.frame(
    id = c("pca", "deg", "volcano", "heatmap", "custom_heatmap", "manual_heatmap",
           "go", "kegg", "gsea", "gsva", "network", "matrix_pca", "matrix_heatmap", "circos", "immune"),
    title = c("RNA-seq 主成分分析", "差异表达分析", "差异表达火山图", "差异或高变基因表达热图",
              "目标基因表达热图", "通路注释差异表达热图", "GO 富集分析", "KEGG 富集分析",
              "GSEA 富集曲线", "GSVA 通路评分", "蛋白质相互作用网络（PPI）", "数值矩阵主成分分析",
              "数值矩阵热图", "基因组环形图（Circos）", "免疫浸润评分"),
    category = c(rep("表达与差异", 3), rep("热图与注释", 3), rep("通路与网络", 5), rep("通用绘图", 3), "通路与网络"),
    description = c(
      "Count → VST → 高变基因 PCA；导出坐标与负荷。",
      "DESeq2 模型、完整结果及上调/下调筛选。",
      "由差异分析输出的完整结果表生成火山图。",
      "读取 VST 等处理后表达矩阵，可按差异结果或高变基因绘制。 ",
      "从处理后表达矩阵按目标基因列表绘制。 ",
      "保留 Excel GeneAnnotation 与一基因多通路布局。",
      "本地人或小鼠 GO 注释或用户提供的 GO GMT；记录来源。",
      "使用有明确来源和版本的本地 KEGG GMT。",
      "完整有效 Wald stat 排序；在整份 GMT 范围检验。",
      "使用已有 VST 或归一化表达矩阵计算 GSVA，再用 limma 比较。 ",
      "Node + Edge 分开导入，支持蛋白或基因 ID；导出交互网络和矩阵。",
      "已处理矩阵，首列为行 ID，数值列为样本；不拟合 DESeq2。",
      "已处理矩阵的变换、行标准化、距离与聚类。",
      "染色体长度、基因区域及区域连线的可复现圈图。", "使用本地免疫标志基因集对各样本计算 ssGSEA 分数。"),
    kind = c(rep("rnaseq", 4), "legacy", "legacy", rep("pathway", 5), rep("matrix", 2), "genome", "matrix"),
    stringsAsFactors = FALSE
  )
  rbind(tools, data.frame(id = "figure_layout", title = "科研图片排版", category = "通用绘图",
    description = "裁切外缘留白，按阅读顺序组合不同大小的面板，可在浏览器中微调。", kind = "image"),
    data.frame(id = tb_general_tools, title = tb_general_titles,
    category = "通用绘图", description = tb_general_help, kind = "matrix"))
}

tb_default_settings <- function(project_root) {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  result <- list(
    inputs = c(list(
      counts = "",
      groups = "",
      targets = "",
      annotation = "",
      deg = "",
      gmt = "", nodes = "", edges = "", matrix = "", chromosomes = "", features = "", links = ""), stats::setNames(rep(list(""), 12), tb_panel_fields(12))),
    params = list(downstream_input = FALSE, panel_count = 4, panel_columns = 0, panel_trim = 3, immune_source = "auto",
      immune_terms = character(), species = "mouse", pathway_source = "auto", immune_min_genes = 5, sankey_gap = .1, kmeans_k = 3, kmeans_seed = 1,
      kmeans_scale = TRUE, beeswarm_log = FALSE, beeswarm_box = TRUE, radar_normalize = TRUE,
      control = "Control", treatment = "Treatment", group_mode = "pair", group_subset = character(), model_groups = character(), min_count = 10, min_samples = 3,
      alpha = 0.05, ora_fdr = 0.05, padj = 0.05, log2fc = 1, pca_top = 500, pca_scale = FALSE,
      heatmap_top = 50, heatmap_mode = "deg", row_scale = TRUE,
      cluster_rows = TRUE, cluster_columns = FALSE, column_cluster_mode = "within", distance = "pearson", linkage = "complete",
      labels = FALSE, direction = "all", gmt_id_type = "SYMBOL", database_version = "",
      go_ontology = "BP", ppi_score = 0.7, ppi_require_edges = FALSE, ppi_reference = FALSE, matrix_transform = "none", custom_transform = "log2",
      matrix_use_groups = FALSE, network_mode = "files", network_layout = "fr", network_score_scale = "auto",
      log_pseudocount = 1, use_batch = FALSE, covariates = "", min_set_size = 10,
      max_set_size = 500, pathway_top = 15, gsea_sort = "padj", gsea_order = "asc", pathway_id = "", pathway_terms = "", fit_type = "parametric"),
    style = list(width = 10, height = 8, dpi = 300, base_size = 16, point_size = 3,
                 point_alpha = 0.8, label_size = 4, legend_position = "right",
                 low = "#3E6AAE", mid = "#E5DEDE", high = "#DFB1BB", up = "#D99A9F",
                 down = "#7897B8", neutral = "#BEBBBA", z_limit = 2,
                 formats = c("png", "svg", "tiff", "pdf")))
  result$style <- utils::modifyList(result$style, tb_style_defaults())
  result
}

tb_dependency_report <- function() {
  packages <- c("shiny", "processx", "jsonlite", "digest", "zip", "rlang", "DESeq2",
                "SummarizedExperiment", "ggplot2", "ggrepel", "scatterplot3d",
                "ComplexHeatmap", "circlize", "svglite", "readxl", "clusterProfiler",
                "org.Hs.eg.db", "org.Mm.eg.db", "GO.db", "AnnotationDbi", "fgsea", "BiocParallel",
                "GSVA", "limma", "igraph", "patchwork", "ggbeeswarm", "magick", "png")
  # 某些受限 Windows 会话可读取具体包却不能枚举整个库；按包读取 DESCRIPTION。
  version <- vapply(packages, function(package) {
    path <- find.package(package, quiet = TRUE)
    if (!length(path)) return(NA_character_)
    tryCatch(unname(read.dcf(file.path(path, "DESCRIPTION"), fields = "Version")[1, 1]),
               error = function(e) NA_character_)
  }, character(1))
  data.frame(package = packages, installed = !is.na(version), version = version,
             role = c(rep("界面 / 任务 / 输出", 6), rep("按所选分析功能加载", length(packages) - 6)),
             stringsAsFactors = FALSE)
}

tb_fail <- function(code, message, files = character(), hint = NULL, parent = NULL) {
  rlang::abort(message, class = "bioworkbench_error", code = code, files = files,
    hint = hint, parent = parent, call = NULL)
}

tb_with_input <- function(files, expr, code = "BW-I03") {
  tryCatch(expr, error = function(e) {
    if (inherits(e, "bioworkbench_error")) stop(e)
    hint <- if (code == "BW-I05") "请确认文件能正常打开，且为不超过 1 亿像素的单帧 PNG、JPEG 或 TIFF。"
      else "请按上传项的说明核对表头、数值、分隔符或样本 ID。"
    tb_fail(code, conditionMessage(e), files, hint, parent = e)
  })
}

tb_error_text <- function(e, spec = NULL, fallback = "BW-S01") {
  files <- e$files %||% character()
  for (i in seq_along(files)) {
    field <- match(files[i], unlist(spec$inputs))
    if (!is.na(field)) {
      key <- names(unlist(spec$inputs))[field]
      files[i] <- (spec$input_names[[key]] %||% basename(spec$origin_inputs[[key]] %||% files[i]))
    } else files[i] <- basename(files[i])
  }
  message <- if (inherits(e, "bioworkbench_error")) e$message else conditionMessage(e)
  paste0("[", e$code %||% fallback, "] ", message,
    if (length(files)) paste0("\n文件：", paste(unique(files), collapse = "、")),
    if (!is.null(e$hint)) paste0("\n处理方法：", e$hint))
}

tb_read_preview <- function(path, n = 200) tb_with_input(path, {
  if (!file.exists(path)) stop("文件不存在：", path)
  separator <- if (tolower(tools::file_ext(path)) %in% c("tsv", "txt")) "\t" else ","
  utils::read.table(path, header = TRUE, sep = separator, nrows = n,
                    check.names = FALSE, stringsAsFactors = FALSE,
                    quote = "\"", comment.char = "", fileEncoding = "UTF-8-BOM")
}, code = "BW-I02")

tb_normalize_spec <- function(spec, root) {
  defaults <- tb_default_settings(dirname(root))
  if (!is.list(spec) || !spec$tool %in% tb_tool_catalog()$id) stop("请选择有效工具。")
  spec$inputs <- utils::modifyList(lapply(defaults$inputs, function(x) ""), spec$inputs %||% list())
  for (field in c("params", "style")) {
    spec[[field]] <- utils::modifyList(defaults[[field]], spec[[field]] %||% list())
  }
  if (spec$tool %in% tb_pathway_tools) {
    source <- spec$params$pathway_source
    choices <- unname(tb_pathway_sources(spec$tool))
    if (identical(source, "auto")) source <- if (nzchar(spec$inputs$gmt)) "custom" else choices[1]
    if (!source %in% choices) stop("参考注释库不适用于此工具。")
    spec$params$pathway_source <- source
    if (source != "custom") spec$inputs$gmt <- ""
  }
  if (spec$tool %in% tb_pathway_tools && spec$params$pathway_source == "go")
    spec$params$go_ontology <- tb_go_ontologies(spec$params$go_ontology)
  if (spec$tool == "figure_layout") spec$style <- tb_figure_paper(spec$style)
  if (spec$tool == "immune") {
    source <- spec$params$immune_source
    if (identical(source, "auto")) source <- if (nzchar(spec$inputs$gmt)) "custom" else "cell"
    if (!source %in% c("cell", "state", "disease", "go", "kegg", "custom")) stop("请选择有效的免疫基因集。")
    spec$params$immune_source <- source
    if (source != "custom") spec$inputs$gmt <- ""
  }
  spec$schema_version <- "1.0"
  spec
}

tb_processed_tools <- c("heatmap", "custom_heatmap", "manual_heatmap", "go", "kegg", "gsea", "gsva")

tb_use_processed <- function(spec) isTRUE(spec$params$downstream_input) || nzchar(spec$inputs$matrix) ||
  (spec$tool %in% c("go", "kegg", "gsea") && nzchar(spec$inputs$deg))

tb_active_inputs <- function(spec) {
  if (spec$tool %in% tb_general_tools) return("matrix")
  switch(spec$tool,
    matrix_pca = c("matrix", if (isTRUE(spec$params$matrix_use_groups)) "groups"),
    matrix_heatmap = c("matrix", if (isTRUE(spec$params$matrix_use_groups)) "groups"),
    figure_layout = tb_panel_fields(spec$params$panel_count),
    immune = c("matrix", if (spec$params$immune_source == "custom") "gmt"),
    circos = c("chromosomes", "features", "links"),
    volcano = if (tb_use_processed(spec) || nzchar(spec$inputs$deg)) "deg" else c("counts", "groups"),
    heatmap = if (tb_use_processed(spec)) c("matrix", "groups", if (spec$params$heatmap_mode == "deg") "deg") else c("counts", "groups"),
    custom_heatmap = c(if (tb_use_processed(spec)) "matrix" else "counts", "groups", "targets"),
    manual_heatmap = c(if (tb_use_processed(spec)) c("matrix", "deg") else "counts", "groups", "annotation"),
    go =, kegg =, gsea = c(if (tb_use_processed(spec)) "deg" else c("counts", "groups"), "gmt"),
    gsva = c(if (tb_use_processed(spec)) "matrix" else "counts", "groups", "gmt"),
    network = switch(spec$params$network_mode, files = c("nodes", "edges"), results = c("deg", "edges"),
      c("counts", "groups", "edges")), c("counts", "groups"))
}

tb_validate_inputs <- function(spec, root) {
  spec <- tb_normalize_spec(spec, root)
  needed <- tb_active_inputs(spec)
  if (spec$tool == "circos") needed <- "chromosomes"
  if (spec$tool %in% tb_pathway_tools && spec$params$pathway_source != "custom") needed <- setdiff(needed, "gmt")
  if (spec$tool == "network" && spec$params$network_mode %in% c("deg", "results") &&
      isTRUE(spec$params$ppi_reference) && !nzchar(spec$inputs$edges)) needed <- setdiff(needed, "edges")
  species <- spec$params$species
  if (!species %in% unname(tb_species_choices)) stop("请选择人或小鼠。")
  if (spec$tool == "immune" && spec$params$immune_source == "custom" && !nzchar(trimws(spec$params$database_version))) stop("请填写免疫标志基因集来源与版本。")
  for (field in needed) {
    value <- spec$inputs[[field]]
    if (length(value) != 1L || is.na(value) || !nzchar(value) || !file.exists(value) || dir.exists(value)) {
      tb_fail("BW-I01", paste0("未找到可读取的输入文件（", field, "）。"),
        if (length(value) == 1L && !is.na(value) && nzchar(value)) value, "请重新上传，或检查本机文件路径。")
    }
  }
  for (field in intersect(needed, c("counts", "groups", "matrix", "deg", "targets", "chromosomes"))) {
    tb_read_preview(spec$inputs[[field]], n = 0L)
  }
  if ("annotation" %in% needed) {
    path <- spec$inputs$annotation
    if (!requireNamespace("readxl", quietly = TRUE))
      tb_fail("BW-R03", "读取 Excel 注释需要 readxl。", path)
    header <- tb_with_input(path, names(readxl::read_excel(path, sheet = "GeneAnnotation", n_max = 0)),
      code = "BW-I02")
    missing <- setdiff(c("GeneKey", "Pathway"), header)
    if (length(missing)) tb_fail("BW-I03", paste("GeneAnnotation 缺少列", paste(missing, collapse = "、")), path,
      "请检查工作表名称 GeneAnnotation，并补齐必需列。")
  }
  if ("nodes" %in% needed) {
    header <- tolower(names(tb_read_preview(spec$inputs$nodes, n = 0)))
    if (!any(c("id", "string_id", "gene_id", "name", "node", "protein_id") %in% header)) tb_fail("BW-I03", "Node 表需有 id / STRING_id / gene_id 等唯一标识列。", spec$inputs$nodes)
  }
  if ("edges" %in% needed) {
    header <- tolower(names(tb_read_preview(spec$inputs$edges, n = 0)))
    if (!any(c("from", "source", "source_id", "node1", "protein1") %in% header) ||
        !any(c("to", "target", "target_id", "node2", "protein2") %in% header)) tb_fail("BW-I03", "Edge 表需有 from/to 或 source/target；请确认没有将节点表放入 Edge 上传位。", spec$inputs$edges)
  }
  p <- spec$params
  heatmap <- spec$tool %in% c("heatmap", "custom_heatmap", "manual_heatmap", "matrix_heatmap", "manual_heatmap", "gsva")
  model <- "counts" %in% needed && spec$tool != "custom_heatmap"
  if (model && (p$min_samples < 1 || p$min_count < 0 || p$alpha <= 0 || p$alpha > 1)) stop("模型 Count、样本数和 alpha 范围不合法。")
  if (spec$tool %in% c("deg", "volcano", "heatmap", "manual_heatmap", "go", "kegg") || (spec$tool == "network" && p$network_mode %in% c("deg", "results"))) {
    if (!is.finite(p$padj) || p$padj <= 0 || p$padj > 1 || !is.finite(p$log2fc) || p$log2fc < 0) stop("FDR 必须在 (0,1]，log2FC 幅度不能为负。")
  }
  if (spec$tool %in% c("go", "kegg") && (!is.finite(p$pathway_top) || p$pathway_top < 1 || p$pathway_top != floor(p$pathway_top)))
    stop("出图条目数须为正整数。")
  if (spec$tool %in% c("go", "kegg") && (!is.finite(p$ora_fdr) || p$ora_fdr <= 0 || p$ora_fdr > 1))
    stop("通路 FDR 阈值须在 (0, 1]。")
  if (spec$tool == "gsea" && (!p$gsea_sort %in% c("padj", "pval") || !p$gsea_order %in% c("asc", "desc") ||
      !is.finite(p$pathway_top) || p$pathway_top != floor(p$pathway_top) || p$pathway_top < 1 || p$pathway_top > 100))
    stop("请设置有效的 GSEA 排序和 1–100 张曲线。")
  if (heatmap && !p$column_cluster_mode %in% c("within", "global")) stop("无效的列聚类范围。")
  if (heatmap && p$linkage == "ward.D2" && p$distance != "euclidean") stop("Ward.D2 必须搭配欧氏距离。")
  if (spec$tool %in% c("pca", "matrix_pca") && p$pca_top < 2) stop("PCA 至少需要两个特征。")
  if (heatmap && p$heatmap_top < 1) stop("热图 Top N 至少为 1。")
  if (spec$tool %in% c("go", "kegg", "gsea", "gsva")) {
    if (p$min_set_size < 1 || p$max_set_size < p$min_set_size) stop("基因集大小范围不合法。")
    if (p$pathway_source == "custom" && !nzchar(trimws(p$database_version))) stop("请填写 GMT 的实际来源和版本。")
  }
  if (spec$tool == "network" && (!is.finite(p$ppi_score) || p$ppi_score < 0 || p$ppi_score > 1)) stop("PPI 筛选分数须位于 [0,1]。")
  if (spec$params$group_mode != "pair") tb_group_plan(spec)
  tryCatch(tb_validate_style(spec), error = function(e)
    tb_fail("BW-S02", conditionMessage(e), hint = "请调整绘图样式或导出设置。", parent = e))
  data.frame(check = c(paste0("输入：", needed), "参数范围"), status = "通过", stringsAsFactors = FALSE)
}

tb_validate_style <- function(spec) {
  if (spec$tool == "figure_layout") {
    spec$style <- tb_figure_paper(spec$style)
    pixels <- c(spec$style$width, spec$style$height) * spec$style$dpi
    if (any(pixels > 16384) || prod(round(pixels)) > 1e8) stop("排版画布最多 1 亿像素且单边不超过 16384 像素。请降低画布尺寸或 dpi。")
  }
  if (spec$tool == "figure_layout") tb_figure_layout_options(spec$style, spec$params$panel_count)
  tb_gradient_colors(spec$style, character())
  schema <- do.call(c, unname(tb_style_schema(spec$tool)))
  if (spec$tool %in% c("go", "kegg") && spec$style$enrichment_kind == "bar") schema[c("enrichment_size_min", "enrichment_size_max")] <- NULL
  if (spec$tool == "network" && !isTRUE(spec$style$network_labels)) schema[c("network_label_top", "label_size")] <- NULL
  if (spec$tool == "network" && !spec$style$network_color_by %in% c("auto", "log2FC")) schema[c("network_low", "network_mid", "network_high")] <- NULL
  if (spec$tool == "network" && spec$style$network_color_by == "log2FC") schema$network_node_color <- NULL
  for (name in names(schema)) {
    definition <- schema[[name]]
    value <- spec$style[[name]]
    if (definition$type == "number" && (length(value) != 1L || !is.finite(value) || value < definition$min || value > definition$max)) stop("样式参数范围不合法：", definition$label)
    if (definition$type == "color") tryCatch(grDevices::col2rgb(value), error = function(e) stop("无效颜色：", definition$label))
    if (definition$type == "select" && !as.character(value) %in% unname(definition$choices)) stop("无效选项：", definition$label)
  }
  if (spec$tool != "deg") {
    if (!length(spec$style$formats) || !all(spec$style$formats %in% c("png", "svg", "tiff", "pdf"))) stop("至少选择一种输出格式。")
    if (spec$style$width * spec$style$height * spec$style$dpi^2 > 1e8) stop("位图超过一亿像素，请减小尺寸或 DPI。")
  }
  if (spec$tool == "network" && spec$style$node_size_min > spec$style$node_size_max) stop("最小节点不能大于最大节点。")
  if (spec$tool %in% c("go", "kegg") && spec$style$enrichment_kind == "dot" && spec$style$enrichment_size_min > spec$style$enrichment_size_max) stop("最小气泡不能大于最大气泡。")
  invisible(TRUE)
}

tb_status_write <- function(directory, status, progress = 0, summary = "", error = NULL) {
  value <- list(status = status, progress = progress, summary = summary, error = error,
                updated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  path <- file.path(directory, "status.json")
  temporary <- paste0(path, ".tmp")
  jsonlite::write_json(value, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null")
  # Windows 不支持 rename 覆盖现有文件；读者对短暂缺失只显示等待。
  if (file.exists(path)) unlink(path)
  if (!file.rename(temporary, path)) stop("无法写入任务状态。")
  invisible(value)
}

tb_launch_job <- function(spec, root, redraw_from = NULL) {
  for (package in c("processx", "jsonlite")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("缺少界面依赖：", package)
  }
  if (is.null(redraw_from)) {
    spec <- tb_normalize_spec(spec, root)
    tb_validate_inputs(spec, root)
  } else {
    saved <- readRDS(file.path(redraw_from, "request.rds"))
    if (saved$tool != spec$tool || tb_read_job(redraw_from)$status != "completed" ||
        !any(file.exists(file.path(redraw_from, c("render.rds", "batch.rds"))))) stop("当前工具没有可重新绘图的已完成结果。")
    saved$style <- spec$style
    spec <- tb_normalize_spec(saved, root)
    tb_validate_style(spec)
    spec$redraw_from <- normalizePath(redraw_from, winslash = "/")
  }
  id <- paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", substr(basename(tempfile()), 1, 12))
  directory <- file.path(root, "results", "toolbox", "jobs", id)
  dir.create(file.path(directory, "inputs"), recursive = TRUE)
  spec$origin_inputs <- spec$inputs
  spec$inputs[setdiff(names(spec$inputs), tb_active_inputs(spec))] <- ""
  # 快照保证浏览器上传临时文件在会话结束后仍可用于复现。
  for (field in if (is.null(redraw_from)) names(spec$inputs) else character()) {
    source <- spec$inputs[[field]]
    if (nzchar(source) && file.exists(source)) {
      target <- file.path(directory, "inputs", paste0(field, ".", tools::file_ext(source)))
      if (!file.copy(source, target)) stop("无法保存输入快照：", field)
      spec$inputs[[field]] <- normalizePath(target, winslash = "/")
    }
  }
  if (is.null(redraw_from) && !is.null(spec$upstream_deg)) {
    source <- file.path(spec$upstream_deg, "outputs")
    target <- file.path(directory, "inputs", "upstream", "outputs")
    dir.create(target, recursive = TRUE)
    files <- list.files(source, recursive = TRUE, pattern = "^(comparisons|deg_all|vst|sample_mapping)[.]csv$")
    for (name in files) {
      copy <- file.path(target, name)
      dir.create(dirname(copy), recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(file.path(source, name), copy)) stop("无法保存上游差异结果：", name)
    }
    spec$upstream_deg <- dirname(target)
  }
  saveRDS(spec, file.path(directory, "request.rds"))
  jsonlite::write_json(spec, file.path(directory, "parameters.json"), pretty = TRUE, auto_unbox = TRUE)
  tb_status_write(directory, "queued", summary = "已保存输入与参数，等待 R 后台进程。")
  executable <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  log <- file.path(directory, "job.log")
  process <- tryCatch(processx::process$new(
    executable, c("--vanilla", file.path(root, "toolbox_worker.R"), directory, root),
    stdout = log, stderr = "2>&1", wd = root, windows_hide_window = TRUE,
    cleanup = TRUE, cleanup_tree = TRUE
  ), error = function(error) {
    tb_status_write(directory, "failed", error = tb_error_text(error, spec, "BW-R01"))
    stop(error)
  })
  job <- list(process = process, directory = directory, id = id, tool = spec$tool)
  # 服务级引用让浏览器会话释放后仍保留任务；关闭 R 服务则由 processx 清理子进程。
  .tb_jobs[[id]] <- job
  job
}

tb_lookup_job <- function(directory) .tb_jobs[[basename(directory)]]

tb_read_status <- function(directory) {
  path <- file.path(directory, "status.json")
  result <- if (file.exists(path)) tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL) else NULL
  result %||% list(status = "queued", progress = 0, summary = "等待任务状态。", error = NULL)
}

tb_read_job <- function(directory) {
  result <- tb_read_status(directory)
  log <- file.path(directory, "job.log")
  result$log <- if (file.exists(log)) paste(tail(readLines(log, warn = FALSE, encoding = "UTF-8"), 160), collapse = "\n") else ""
  result$files <- list.files(file.path(directory, "outputs"), recursive = TRUE, full.names = TRUE)
  result
}

tb_stop_job <- function(job) {
  if (job$process$is_alive()) job$process$kill_tree()
  tb_status_write(job$directory, "cancelled", summary = "任务已停止；未完成输出不视为有效结果。")
  invisible(NULL)
}

tb_list_runs <- function(root) {
  directory <- file.path(root, "results", "toolbox", "jobs")
  paths <- list.dirs(directory, full.names = TRUE, recursive = FALSE)
  records <- lapply(rev(sort(paths)), function(path) {
    request <- file.path(path, "request.rds")
    if (!file.exists(request)) return(NULL)
    spec <- tryCatch(readRDS(request), error = function(e) NULL)
    if (is.null(spec)) return(NULL)
    state <- tb_read_status(path)
    data.frame(id = basename(path), tool = spec$tool, status = state$status, directory = path,
                created = format(file.info(request)$mtime, "%Y-%m-%d %H:%M:%S"), stringsAsFactors = FALSE)
  })
  records <- Filter(Negate(is.null), records)
  if (!length(records)) return(data.frame(id = character(), tool = character(), status = character(),
                                         directory = character(), created = character()))
  do.call(rbind, records)
}

tb_write_reproduce <- function(spec, path, root) {
  # R 配方是显式用户下载的可执行脚本；启动界面不会执行它。
  lines <- c("# 本地工具箱复现配方；运行会实际执行所选分析。",
             paste0("root <- ", encodeString(normalizePath(root, winslash = "/"), quote = '"')),
             "source(file.path(root, 'R', 'toolbox.R'), encoding = 'UTF-8')",
             paste0("spec <- ", paste(capture.output(dput(spec)), collapse = "\n")),
             "job <- tb_launch_job(spec, root, redraw_from = spec$redraw_from)", "job$process$wait()",
             "state <- tb_read_job(job$directory)", "if (state$status != 'completed') stop(state$error %||% state$summary)",
             "cat('结果目录：', job$directory, '\\n')")
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}

tb_zip_results <- function(directory, file) {
  if (!requireNamespace("zip", quietly = TRUE)) stop("下载结果包需要 zip 包。")
  if (tb_read_job(directory)$status != "completed") stop("只能打包成功完成的任务。")
  stage <- tempfile()
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  main <- "01_图与作图数据"
  extra <- "02_分析与注释"
  for (folder in c(main, extra)) dir.create(file.path(stage, folder))
  output <- file.path(directory, "outputs")
  files <- list.files(output, recursive = TRUE)
  for (name in files) {
    target <- file.path(stage, if (tb_plot_file(name)) main else extra, name)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(output, name), target)) stop("结果打包失败：", name)
  }
  extras <- file.path(directory, c("parameters.json", "job.log", "reproduce.R"))
  file.copy(extras[file.exists(extras)], file.path(stage, extra))
  zip::zipr(file, c(main, extra), root = stage, include_directories = TRUE)
  invisible(file)
}

tb_plot_file <- function(path) {
  name <- basename(path)
  grepl("[.](png|svg|tiff|pdf|html|js)$", name, ignore.case = TRUE) ||
    grepl("(^plot_data|_PlotData|_PlotMatrix|^loading_plot_data)[.]csv$", name, ignore.case = TRUE) ||
    name %in% c("CYTOSCAPE-LICENSE.txt", "ppi_nodes.csv", "ppi_edges.csv", "features.csv", "links.csv", "venn_regions.csv", "figure_panels.csv", "gsea_plot_index.csv")
}

tb_project_inputs <- function(path) {
  files <- list.files(path, full.names = TRUE, recursive = FALSE)
  files <- files[file.exists(files) & !dir.exists(files)]
  stems <- tolower(tools::file_path_sans_ext(basename(files)))
  extensions <- tolower(tools::file_ext(files))
  use <- !grepl("normalized|normalised|vst|tpm|fpkm|filtered|output|result|plot", stems)
  patterns <- c(counts = "count", groups = "group|sample[_ -]?metadata", annotation = "annotation|注释")
  if (!length(files)) return(character())
  matches <- vapply(patterns, function(pattern) grepl(pattern, stems), logical(length(files)))
  unambiguous <- rowSums(matrix(matches, ncol = length(patterns))) == 1L
  found <- lapply(names(patterns), function(name) {
    allowed <- if (name == "annotation") "xlsx" else c("csv", "tsv", "txt")
    hits <- files[use & unambiguous & extensions %in% allowed & grepl(patterns[[name]], stems)]
    if (length(hits) == 1L) normalizePath(hits, winslash = "/") else ""
  })
  values <- stats::setNames(unlist(found), names(patterns))
  values[nzchar(values)]
}

tb_panel_fields <- function(count) {
  if (length(count) != 1L || !is.finite(count) || count != floor(count) || count < 2L || count > 12L)
    stop("图片数量须为 2–12 的整数。")
  sprintf("panel_%02d", seq_len(count))
}

tb_parse_terms <- function(text) {
  terms <- trimws(strsplit(text, "[,;，；[:space:]]+")[[1L]])
  unique(terms[nzchar(terms)])
}

tb_read_groups <- function(path) {
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
  if (!nrow(samples) || anyNA(samples$condition) || any(!nzchar(trimws(samples$condition))))
    stop("纳入的样本必须有非空分组。")
  samples$condition <- trimws(as.character(samples$condition))
  samples
}

tb_joint_tool <- function(tool, params) tool %in% c("pca", "custom_heatmap") ||
  (tool == "heatmap" && identical(params$heatmap_mode, "variable"))

tb_group_plan <- function(spec) {
  p <- spec$params
  mode <- p$group_mode
  if (mode == "pair") return(NULL)
  supported <- c("pca", "deg", "volcano", "heatmap", "custom_heatmap", "manual_heatmap", tb_pathway_tools, "network")
  if (!spec$tool %in% supported || (spec$tool == "network" && p$network_mode != "deg") ||
      (nzchar(spec$inputs$deg) && spec$tool != "gsva")) stop("此输入模式不支持按分组批量比较。")
  if (spec$tool %in% c("pca", "custom_heatmap") && mode != "joint")
    stop("此工具支持指定两组或多组联合展示。")
  if (mode == "joint" && !tb_joint_tool(spec$tool, p)) stop("此工具需要明确的比较方向，请选择对照比较或两两比较。")
  samples <- tb_with_input(spec$inputs$groups, tb_read_groups(spec$inputs$groups))
  groups <- unique(as.character(samples$condition))
  if (length(p$group_subset)) {
    if (!all(p$group_subset %in% groups)) stop("部分所选组在分组表中不存在或未纳入。")
    groups <- groups[groups %in% p$group_subset]
  }
  if (length(groups) < 2L) stop("至少纳入两个组。")
  if (mode == "joint") return(list(groups = groups, pairs = NULL))
  if (mode == "reference" && !p$control %in% groups) stop("请选择纳入分析的对照组。")
  pairs <- if (mode == "reference") data.frame(control = p$control, treatment = setdiff(groups, p$control))
    else if (mode == "all_pairs") {
      combinations <- utils::combn(groups, 2L)
      data.frame(control = combinations[1L, ], treatment = combinations[2L, ])
    } else stop("请选择有效的分组分析模式。")
  list(groups = groups, pairs = pairs)
}

tb_link_deg_outputs <- function(spec, directory) {
  tool <- spec$tool
  if (tool == "network") spec$params$network_mode <- "results"
  spec$params$downstream_input <- tool %in% tb_processed_tools
  spec$inputs$counts <- ""
  if (tool %in% c("heatmap", "gsva")) {
    spec$inputs$matrix <- file.path(directory, "vst.csv")
    spec$inputs$groups <- file.path(directory, "sample_mapping.csv")
  }
  if (tool != "gsva") spec$inputs$deg <- file.path(directory, "deg_all.csv")
  spec
}

tb_gsea_image_labels <- function(files) {
  labels <- basename(files)
  for (folder in unique(dirname(dirname(files)))) {
    index <- file.path(folder, "gsea_plot_index.csv")
    if (!file.exists(index)) next
    rows <- utils::read.csv(index, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
    at <- which(dirname(dirname(files)) == folder)
    item <- match(basename(dirname(files[at])), rows$folder)
    valid <- !is.na(item)
    labels[at[valid]] <- paste0(item[valid], ". ", rows$pathway_name[item[valid]],
      " [", rows$pathway_id[item[valid]], "]")
  }
  labels
}

tb_go_ontologies <- function(value) {
  supported <- c("BP", "CC", "MF")
  if ("ALL" %in% value) return(supported)
  if (!length(value) || !all(value %in% supported)) stop("请至少选择一个 GO 分类（BP、CC 或 MF）。")
  supported[supported %in% value]
}
