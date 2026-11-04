toolbox_source <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (!is.null(toolbox_source)) source(file.path(dirname(toolbox_source), "style_schema.R"), encoding = "UTF-8")
# 本地工具箱公共接口；加载本文件不会拟合模型、联网或生成科研图片。
`%||%` <- function(x, y) if (is.null(x)) y else x
if (!exists(".tb_jobs", inherits = FALSE)) .tb_jobs <- new.env(parent = emptyenv())

tb_tool_catalog <- function() {
  data.frame(
    id = c("pca", "deg", "volcano", "heatmap", "custom_heatmap", "manual_heatmap",
           "go", "kegg", "gsea", "gsva", "network", "matrix_pca", "matrix_heatmap", "circos"),
    title = c("RNA-seq PCA", "差异表达分析", "火山图", "差异 / 高变基因热图",
              "自定义基因 Count 热图", "手工通路注释热图", "GO 富集分析", "KEGG 富集分析",
              "GSEA 富集曲线", "GSVA 通路评分", "PPI 网络与矩阵", "通用矩阵 PCA",
              "通用矩阵热图", "Circos 基因组圈图"),
    category = c(rep("表达与差异", 3), rep("热图与注释", 3), rep("通路与网络", 5), rep("通用绘图", 3)),
    description = c(
      "Count → VST → 高变基因 PCA；导出坐标与负荷。",
      "DESeq2 模型、完整结果及上调/下调筛选。",
      "读取已有差异表，或复用 Count 模型生成火山图。",
      "基于 VST 选择差异或高变基因；聚类与颜色分开设置。",
      "沿用项目 Count 热图；可选 log2、log-CPM 或 VST。",
      "保留 Excel GeneAnnotation 与一基因多通路布局。",
      "本地小鼠 GO 注释或用户提供的 GO GMT；记录来源。",
      "使用有明确来源和版本的本地 KEGG GMT。",
      "完整有效 Wald stat 排序；在整份 GMT 范围检验。",
      "VST 上计算 GSVA，再使用同设计的 limma 比较。",
      "Node + Edge 分开导入，支持蛋白或基因 ID；导出交互网络和矩阵。",
      "已处理矩阵，首列为行 ID，数值列为样本；不拟合 DESeq2。",
      "已处理矩阵的变换、行标准化、距离与聚类。",
      "染色体长度、基因区域及区域连线的可复现圈图。"),
    kind = c(rep("rnaseq", 4), "legacy", "legacy", rep("pathway", 5), rep("matrix", 2), "genome"),
    stringsAsFactors = FALSE
  )
}

tb_default_settings <- function(project_root) {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  existing <- function(path) if (file.exists(path)) path else ""
  result <- list(
    inputs = list(
      counts = existing(file.path(project_root, "data/gene_count.csv")),
      groups = existing(file.path(project_root, "data/group.csv")),
      targets = existing(file.path(project_root, "app/config/target_genes.csv")),
      annotation = existing(file.path(project_root, "data/pathway_annotation.xlsx")),
      deg = existing(file.path(project_root, "data/deg_results.csv")),
      gmt = "", nodes = "", edges = "", matrix = "", chromosomes = "", features = "", links = ""),
    params = list(
      control = "M2", treatment = "HA@CuPB", min_count = 10, min_samples = 3,
      alpha = 0.05, padj = 0.05, log2fc = 1, pca_top = 500, pca_scale = FALSE,
      heatmap_top = 50, heatmap_mode = "deg", row_scale = TRUE,
      cluster_rows = TRUE, cluster_columns = FALSE, distance = "pearson", linkage = "complete",
      labels = FALSE, direction = "all", gmt_id_type = "SYMBOL", database_version = "",
      go_ontology = "BP", ppi_score = 0.7, matrix_transform = "none", custom_transform = "log2",
      matrix_use_groups = FALSE, network_mode = "files", network_layout = "fr", network_score_scale = "auto",
      log_pseudocount = 1, use_batch = FALSE, covariates = "", min_set_size = 10,
      max_set_size = 500, pathway_top = 15, pathway_id = "", fit_type = "parametric"),
    style = list(width = 10, height = 8, dpi = 300, base_size = 16, point_size = 3,
                 point_alpha = 0.8, label_size = 4, legend_position = "right",
                 low = "#3E6AAE", mid = "#E5DEDE", high = "#DFB1BB", up = "#D99A9F",
                 down = "#7897B8", neutral = "#BEBBBA", z_limit = 2,
                 formats = c("png", "svg", "tiff", "pdf")))
  result$style <- utils::modifyList(result$style, tb_style_defaults())
  result
}

tb_dependency_report <- function() {
  packages <- c("shiny", "processx", "jsonlite", "digest", "zip", "DESeq2",
                "SummarizedExperiment", "ggplot2", "ggrepel", "scatterplot3d",
                "ComplexHeatmap", "circlize", "svglite", "readxl", "clusterProfiler",
                "org.Mm.eg.db", "GO.db", "AnnotationDbi", "fgsea", "BiocParallel",
                "GSVA", "limma", "igraph", "patchwork")
  # 某些受限 Windows 会话可读取具体包却不能枚举整个库；按包读取 DESCRIPTION。
  version <- vapply(packages, function(package) {
    path <- find.package(package, quiet = TRUE)
    if (!length(path)) return(NA_character_)
    tryCatch(unname(read.dcf(file.path(path, "DESCRIPTION"), fields = "Version")[1, 1]),
               error = function(e) NA_character_)
  }, character(1))
  data.frame(package = packages, installed = !is.na(version), version = version,
             role = c(rep("界面 / 任务 / 输出", 5), rep("按所选分析功能加载", 19)),
             stringsAsFactors = FALSE)
}

tb_read_preview <- function(path, n = 200) {
  if (!file.exists(path)) stop("文件不存在：", path)
  separator <- if (tolower(tools::file_ext(path)) %in% c("tsv", "txt")) "\t" else ","
  utils::read.table(path, header = TRUE, sep = separator, nrows = n,
                    check.names = FALSE, stringsAsFactors = FALSE,
                    quote = "\"", comment.char = "", fileEncoding = "UTF-8-BOM")
}

tb_normalize_spec <- function(spec, root) {
  defaults <- tb_default_settings(dirname(root))
  if (!is.list(spec) || !spec$tool %in% tb_tool_catalog()$id) stop("请选择有效工具。")
  spec$inputs <- utils::modifyList(lapply(defaults$inputs, function(x) ""), spec$inputs %||% list())
  for (field in c("params", "style")) {
    spec[[field]] <- utils::modifyList(defaults[[field]], spec[[field]] %||% list())
  }
  spec$schema_version <- "1.0"
  spec
}

tb_active_inputs <- function(spec) {
  switch(spec$tool,
    matrix_pca = c("matrix", if (isTRUE(spec$params$matrix_use_groups)) "groups"),
    matrix_heatmap = c("matrix", if (isTRUE(spec$params$matrix_use_groups)) "groups"),
    circos = c("chromosomes", "features", "links"),
    volcano = if (nzchar(spec$inputs$deg)) "deg" else c("counts", "groups"),
    custom_heatmap = c("counts", "groups", "targets"),
    manual_heatmap = c("counts", "groups", "annotation"),
    go = c("counts", "groups", "gmt"),
    kegg = c("counts", "groups", "gmt"),
    gsea = c("counts", "groups", "gmt"),
    gsva = c("counts", "groups", "gmt"),
    network = if (spec$params$network_mode == "files") c("nodes", "edges") else c("counts", "groups", "edges"), c("counts", "groups"))
}

tb_validate_inputs <- function(spec, root) {
  spec <- tb_normalize_spec(spec, root)
  needed <- switch(spec$tool, matrix_pca = "matrix", matrix_heatmap = "matrix",
    circos = "chromosomes", volcano = if (nzchar(spec$inputs$deg)) "deg" else c("counts", "groups"),
    custom_heatmap = c("counts", "groups", "targets"), manual_heatmap = c("counts", "groups", "annotation"),
    network = if (spec$params$network_mode == "files") c("nodes", "edges") else c("counts", "groups", "edges"),
    c("counts", "groups"))
  if (spec$tool %in% c("kegg", "gsea", "gsva")) needed <- c(needed, "gmt")
  if (spec$tool %in% c("matrix_pca", "matrix_heatmap") && isTRUE(spec$params$matrix_use_groups)) needed <- c(needed, "groups")
  for (field in needed) {
    value <- spec$inputs[[field]]
    if (length(value) != 1L || !nzchar(value) || !file.exists(value)) {
      stop("请提供有效的 ", field, " 文件。", call. = FALSE)
    }
  }
  if ("nodes" %in% needed) {
    header <- tolower(names(tb_read_preview(spec$inputs$nodes, n = 0)))
    if (!any(c("id", "string_id", "gene_id", "name", "node", "protein_id") %in% header)) stop("Node 表需有 id / STRING_id / gene_id 等唯一标识列。")
  }
  if ("edges" %in% needed) {
    header <- tolower(names(tb_read_preview(spec$inputs$edges, n = 0)))
    if (!any(c("from", "source", "source_id", "node1", "protein1") %in% header) ||
        !any(c("to", "target", "target_id", "node2", "protein2") %in% header)) stop("Edge 表需有 from/to 或 source/target；请确认没有将节点表放入 Edge 上传位。")
  }
  p <- spec$params
  heatmap <- spec$tool %in% c("heatmap", "custom_heatmap", "manual_heatmap", "matrix_heatmap", "gsva")
  model <- any(c("counts", "groups") %in% needed) && !spec$tool %in% c("custom_heatmap", "matrix_pca", "matrix_heatmap")
  if (model && (p$min_samples < 1 || p$min_count < 0 || p$alpha <= 0 || p$alpha > 1)) stop("模型 Count、样本数和 alpha 范围不合法。")
  if (spec$tool %in% c("deg", "volcano", "heatmap", "manual_heatmap", "go", "kegg") || (spec$tool == "network" && p$network_mode == "deg")) {
    if (!is.finite(p$padj) || p$padj <= 0 || p$padj > 1 || !is.finite(p$log2fc) || p$log2fc < 0) stop("FDR 必须在 (0,1]，log2FC 幅度不能为负。")
  }
  if (heatmap && p$linkage == "ward.D2" && p$distance != "euclidean") stop("Ward.D2 必须搭配欧氏距离。")
  if (spec$tool %in% c("pca", "matrix_pca") && p$pca_top < 2) stop("PCA 至少需要两个特征。")
  if (heatmap && p$heatmap_top < 1) stop("热图 Top N 至少为 1。")
  if (spec$tool %in% c("go", "kegg", "gsea", "gsva")) {
    if (p$min_set_size < 1 || p$max_set_size < p$min_set_size) stop("基因集大小范围不合法。")
    if ((spec$tool != "go" || nzchar(spec$inputs$gmt)) && !nzchar(trimws(p$database_version))) stop("请填写 GMT 的实际来源和版本。")
  }
  if (spec$tool == "network" && (!is.finite(p$ppi_score) || p$ppi_score < 0 || p$ppi_score > 1)) stop("PPI 筛选分数须位于 [0,1]。")
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
  data.frame(check = c(paste0("输入：", needed), "参数范围"), status = "通过", stringsAsFactors = FALSE)
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

tb_launch_job <- function(spec, root) {
  for (package in c("processx", "jsonlite")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("缺少界面依赖：", package)
  }
  spec <- tb_normalize_spec(spec, root)
  tb_validate_inputs(spec, root)
  id <- paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", substr(basename(tempfile()), 1, 12))
  directory <- file.path(root, "results", "toolbox", "jobs", id)
  dir.create(file.path(directory, "inputs"), recursive = TRUE)
  spec$origin_inputs <- spec$inputs
  spec$inputs[setdiff(names(spec$inputs), tb_active_inputs(spec))] <- ""
  # 快照保证浏览器上传临时文件在会话结束后仍可用于复现。
  for (field in names(spec$inputs)) {
    source <- spec$inputs[[field]]
    if (nzchar(source) && file.exists(source)) {
      target <- file.path(directory, "inputs", paste0(field, ".", tools::file_ext(source)))
      if (!file.copy(source, target)) stop("无法保存输入快照：", field)
      spec$inputs[[field]] <- normalizePath(target, winslash = "/")
    }
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
    tb_status_write(directory, "failed", error = conditionMessage(error))
    stop(error)
  })
  job <- list(process = process, directory = directory, id = id, tool = spec$tool)
  # 服务级引用让浏览器会话释放后仍保留任务；关闭 R 服务则由 processx 清理子进程。
  .tb_jobs[[id]] <- job
  job
}

tb_lookup_job <- function(directory) .tb_jobs[[basename(directory)]]

tb_read_job <- function(directory) {
  path <- file.path(directory, "status.json")
  result <- if (file.exists(path)) tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL) else NULL
  result <- result %||% list(status = "queued", progress = 0, summary = "等待任务状态。", error = NULL)
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
    state <- tb_read_job(path)
    data.frame(id = basename(path), tool = spec$tool, status = state$status, directory = path,
                created = format(file.info(request)$mtime, "%Y-%m-%d %H:%M:%S"), stringsAsFactors = FALSE)
  })
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
             "job <- tb_launch_job(spec, root)", "job$process$wait()",
             "state <- tb_read_job(job$directory)", "if (state$status != 'completed') stop(state$error %||% state$summary)",
             "cat('结果目录：', job$directory, '\\n')")
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}

tb_zip_results <- function(directory, file) {
  if (!requireNamespace("zip", quietly = TRUE)) stop("下载结果包需要 zip 包。")
  if (tb_read_job(directory)$status != "completed") stop("只能打包成功完成的任务。")
  # 默认只打包结果与参数，不附带 Count 上传快照、模型缓存和浏览器临时文件。
  files <- c("outputs", "parameters.json", "job.log", "reproduce.R")
  files <- files[file.exists(file.path(directory, files))]
  zip::zipr(file, files, root = directory)
  invisible(file)
}
