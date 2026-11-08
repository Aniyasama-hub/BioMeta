# Compile only the selected analysis and its transitive helper functions into
# one R script. No Shiny, worker launcher or source checkout is needed to run it.
tb_portable_definitions <- function(root) {
  modules <- c("style_schema.R", "toolbox.R", "gene_mapping.R", "pathway_options.R", "annotated_heatmap.R", "core.R", "analysis.R", "prepare.R",
    "pathways.R", "ppi_prepare.R", "toolbox_analysis.R", "toolbox_render.R", "group_comparisons.R",
    "network_import.R", "public_pathways.R", "immune.R", "general_plots.R", "general_plot_render.R", "figure_layout.R", "plots.R")
  definitions <- list()
  for (module in modules) for (expr in parse(file.path(root, "R", module), encoding = "UTF-8")) {
    if (is.call(expr) && identical(expr[[1L]], as.name("<-")) && is.symbol(expr[[2L]]))
      definitions[[as.character(expr[[2L]])]] <- expr
  }
  definitions
}

tb_portable_specialize <- function(expr, spec, name) {
  type <- switch(spec$tool, matrix_pca = "pca", matrix_heatmap = "heatmap", custom_heatmap =
    if (nzchar(spec$inputs$matrix)) "heatmap" else "legacy_heatmap", manual_heatmap = "heatmap",
    go = "enrichment", kegg = "enrichment", gsva = "heatmap", immune = "heatmap", spec$tool)
  if (name == "prepare_bundle" && spec$tool == "gsva") type <- "gsva"
  static <- new.env(parent = baseenv())
  static$spec <- spec; static$type <- type; static$bundle <- list(type = type)
  static$tb_pathway_tools <- tb_pathway_tools; static$tb_general_tools <- tb_general_tools
  pure <- c("spec", "type", "bundle", "tb_pathway_tools", "tb_general_tools", "$", "==", "!=", "%in%", "!", "&&", "||", "c", "(", "nzchar", "isTRUE", "is.null")
  symbols <- function(x) {
    if (is.symbol(x)) return(as.character(x))
    if (!is.call(x)) return(character())
    if (identical(x[[1L]], as.name("$"))) return(symbols(x[[2L]]))
    unlist(lapply(as.list(x), symbols), use.names = FALSE)
  }
  walk <- function(x) {
    if (!is.call(x)) return(x)
    if (identical(x[[1L]], as.name("if"))) {
      condition <- x[[2L]]
      names <- symbols(condition)
      text <- paste(deparse(condition), collapse = " ")
      valid <- all(names %in% pure) && ("spec" %in% names ||
        ("type" %in% names && name == "prepare_bundle") ||
        ("bundle" %in% names && grepl("bundle$type", text, fixed = TRUE) &&
          !grepl("bundle", gsub("bundle$type", "", text, fixed = TRUE), fixed = TRUE) &&
          !grepl("collection", text, fixed = TRUE)))
      if (valid) {
        value <- tryCatch(eval(condition, static), error = function(e) NULL)
        if (is.logical(value) && length(value) == 1L && !is.na(value))
          return(if (value) walk(x[[3L]]) else if (length(x) == 4L) walk(x[[4L]]) else quote(invisible(NULL)))
      }
    }
    if (identical(x[[1L]], as.name("switch")) &&
        identical(paste(deparse(x[[2L]]), collapse = ""), "bundle$type")) {
      branches <- as.list(x)
      keep <- seq_along(branches) <= 2L | names(branches) %in% c(type, "")
      return(as.call(lapply(branches[keep], walk)))
    }
    for (i in seq_along(x)[-1L]) {
      # Missing defaults in function pairlists cannot be evaluated as ordinary expressions.
      if (identical(x[[1L]], as.name("function")) && i == 2L) next
      if (identical(x[[i]], quote(expr = ))) next
      x[i] <- list(walk(x[[i]]))
    }
    x
  }
  walk(expr)
}

tb_portable_write <- function(spec, path, root, portable = TRUE) {
  spec <- tb_normalize_spec(spec, root)
  original <- spec
  spec$redraw_from <- NULL
  spec$origin_inputs <- NULL; spec$input_names <- NULL; spec$bulk_review <- NULL
  # Prefer the precise annotation/reference used by a completed run.
  present <- Filter(function(x) is.character(x) && length(x) == 1L && nzchar(x) && file.exists(x), original$inputs)
  directories <- unique(c(dirname(path), unlist(lapply(present, function(x) dirname(dirname(x))), use.names = FALSE)))
  candidates <- c(file.path(directories, "outputs", "config_resolved.txt"),
    file.path(directories, "outputs", "config_resolved.R"))
  resolved <- candidates[file.exists(candidates)]
  config <- NULL
  if (length(resolved)) config <- dget(resolved[1L])
  if (is.null(config)) {
    env <- new.env(parent = baseenv())
    sys.source(file.path(root, "config", "project.R"), env)
    config <- env$config
  }
  public <- file.path(directories, "outputs", "public_annotation.gmt")
  public <- public[file.exists(public)]
  if (length(public) && spec$tool %in% tb_pathway_tools) {
    spec$inputs$gmt <- public[1L]; spec$params$pathway_source <- "custom"; spec$params$gmt_id_type <- "gene_id"
  }
  if (length(public) && (spec$tool == "manual_heatmap" ||
      (spec$tool == "heatmap" && spec$params$heatmap_kind == "annotated")) && spec$params$annotation_mode == "auto") {
    spec$inputs$gmt <- public[1L]; spec$params$annotation_source <- "custom"
  }
  if (length(public) && spec$tool == "immune" && spec$params$immune_source %in% c("go", "kegg")) {
    spec$inputs$gmt <- public[1L]; spec$params$immune_source <- "custom"; spec$params$gmt_id_type <- "gene_id"
  }
  if (spec$tool == "network" && file.exists(config$pathways$ppi_edges %||% "")) {
    spec$inputs$edges <- config$pathways$ppi_edges; spec$params$ppi_reference <- FALSE
  }
  if (spec$tool == "immune" && spec$params$immune_source %in% c("cell", "state", "disease")) {
    reference <- tb_immune_reference(root, spec$params$species, spec$params$immune_source)
    if (file.exists(reference$path)) {
      spec$inputs$gmt <- reference$path; spec$params$immune_source <- "custom"; spec$params$gmt_id_type <- "SYMBOL"
      spec$params$portable_marker_symbols <- TRUE
    }
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  for (key in names(spec$inputs)) {
    source <- spec$inputs[[key]]
    if (!is.character(source) || !nzchar(source)) next
    if (!file.exists(source)) stop("导出独立脚本时输入缺失：", key)
    if (portable) {
      relative <- paste0("data/", key, ".", tools::file_ext(source))
      destination <- file.path(dirname(path), relative)
      dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
      if (!identical(normalizePath(source, winslash = "/"), normalizePath(destination, winslash = "/", mustWork = FALSE)) &&
          !file.copy(source, destination, overwrite = TRUE)) stop("无法导出复现数据：", key)
      spec$inputs[[key]] <- relative
    } else spec$inputs[[key]] <- normalizePath(source, winslash = "/")
  }
  if (!is.null(spec$upstream_deg)) {
    source <- file.path(spec$upstream_deg, "outputs")
    if (portable) {
      destination <- file.path(dirname(path), "data", "upstream")
      dir.create(destination, recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(source, destination, recursive = TRUE)) stop("无法导出多组差异输入。")
      spec$upstream_deg <- "data/upstream"
    }
  }
  definitions <- tb_portable_definitions(root)
  marker <- paste(deparse(definitions$tb_immune_markers, width.cutoff = 95L), collapse = "\n")
  marker <- sub("match_symbols <- FALSE", "match_symbols <- isTRUE(spec$params$portable_marker_symbols)", marker, fixed = TRUE)
  definitions$tb_immune_markers <- parse(text = marker)[[1L]]
  replace <- function(name, fun) definitions[[name]] <<- call("<-", as.name(name), fun)
  replace("tb_engine", quote(function(root) globalenv()))
  replace("tb_normalize_spec", quote(function(spec, root) spec))
  replace("tb_validate_inputs", quote(function(spec, root) {
    paths <- unlist(spec$inputs, use.names = FALSE)
    if (any(nzchar(paths) & !file.exists(paths))) stop("输入文件缺失，请修改脚本顶部的文件地址。")
    if (!length(spec$style$formats) || !all(spec$style$formats %in% c("png", "svg", "tiff", "pdf")))
      stop("导出格式须为 png、svg、tiff、pdf。")
  }))
  replace("tb_status_write", quote(function(...) invisible(NULL)))
  replace("tb_write_reproduce", quote(function(...) invisible(NULL)))
  replace("tb_save_result_copy", quote(function(...) invisible(NULL)))
  replace("tb_config", quote(function(spec, root, directory, engine, with_samples = TRUE) {
    cfg <- analysis_config
    p <- spec$params
    cfg$project$species <- c(human = "Homo_sapiens", mouse = "Mus_musculus")[[p$species]]
    cfg$project$output <- file.path(directory, "outputs")
    cfg$input$counts <- spec$inputs$counts
    cfg$input$original_groups <- spec$inputs$groups
    if (with_samples) {
      samples <- tb_samples(spec$inputs$groups, p)
      cfg$input$samples <- file.path(directory, "inputs", "sample_mapping.csv")
      write_table(samples, cfg$input$samples)
      cfg$project$max_samples <- nrow(samples)
    }
    cfg$analysis$condition_levels <- if (length(p$model_groups)) p$model_groups else c(p$control, p$treatment)
    cfg$contrast <- list(numerator = p$treatment, denominator = p$control)
    cfg$pathways$gmt <- if (nzchar(spec$inputs$gmt)) spec$inputs$gmt else NULL
    cfg$pathways$gmt_id_type <- p$gmt_id_type
    cfg$pathways$ppi_edges <- spec$inputs$edges
    cfg$style <- utils::modifyList(cfg$style, spec$style)
    cfg
  }))
  # Resolve every frontend value with the same config builder as the original run.
  # It only writes sample mapping when with_samples=TRUE, so FALSE is safe here.
  builder <- new.env(parent = globalenv())
  eval(tb_portable_definitions(root)$tb_config, builder)
  engine <- new.env(parent = globalenv())
  engine$load_config <- function(path) config
  config <- builder$tb_config(original, root, dirname(path), engine, with_samples = FALSE)
  config$input$counts <- NULL; config$input$samples <- NULL; config$input$original_groups <- NULL
  config$input[c("salmon_dir", "tx2gene", "reference_manifest")] <- NULL
  config$project$output <- "analysis_results"
  config$selection$target_genes <- NULL; config$pathways$gmt <- NULL; config$pathways$ppi_edges <- NULL
  replace("tb_model", quote(function(cfg, engine, root, directory) {
    samples <- read_samples(cfg)
    make_design(samples, cfg)
    analysis <- analyze_dataset(cfg, samples, file.path(directory, "model"), list())
    write_table(analysis$samples, file.path(directory, "outputs", "sample_mapping.csv"))
    analysis
  }))
  # Interactive browser editors are separate from a scientific R analysis.
  replace("tb_prepare_ppi_topology", quote(function(...) NULL))
  replace("tb_write_interactive_network", quote(function(...) invisible(NULL)))
  if (spec$tool == "deg") replace("tb_render_request", quote(function(...) invisible(NULL)))
  figure <- definitions$tb_render_figure
  body <- as.list(figure[[3L]][[3L]])
  index <- which(vapply(body, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) && identical(x[[2L]], as.name("config")), logical(1)))
  if (length(index)) {
    figure[[3L]][[3L]] <- as.call(body[seq_len(index[1L] - 1L)])
    definitions$tb_render_figure <- figure
  }
  # Legacy count heatmaps keep their scientific implementation embedded as R
  # expressions, with the source adapter and rendering file reads removed.
  legacy <- NULL
  if (spec$tool == "custom_heatmap" && !nzchar(spec$inputs$matrix)) {
    legacy <- parse(file.path(dirname(root), "legacy", "04.4_custom_gene_count_heatmap.R"), encoding = "UTF-8")
    substitute_read <- function(x) {
      if (!is.call(x)) return(x)
      if (identical(x[[1L]], as.name("parse"))) return(as.name("legacy_code"))
      if (identical(x[[1L]], as.name("digest::digest"))) return(x)
      for (i in seq_along(x)[-1L]) {
        if (identical(x[[1L]], as.name("function")) && i == 2L) next
        if (!identical(x[[i]], quote(expr = ))) x[i] <- list(substitute_read(x[[i]]))
      }
      x
    }
    definitions$tb_run_legacy <- substitute_read(definitions$tb_run_legacy)
    definitions$tb_render_legacy <- substitute_read(definitions$tb_render_legacy)
    legacy_prepare <- definitions$tb_legacy_heatmap
    text <- paste(deparse(legacy_prepare, width.cutoff = 95L), collapse = "\n")
    text <- sub("sha256 = digest::digest(file = source, algo = \"sha256\")", 'sha256 = "embedded-in-script"', text, fixed = TRUE)
    definitions$tb_legacy_heatmap <- parse(text = text)[[1L]]
  }
  definitions <- lapply(names(definitions), function(name) tb_portable_specialize(definitions[[name]], spec, name)) |>
    stats::setNames(names(definitions))
  needed <- "tb_run_request"
  repeat {
    refs <- unique(unlist(lapply(definitions[needed], all.names), use.names = FALSE))
    next_needed <- union(needed, intersect(refs, names(definitions)))
    if (setequal(needed, next_needed)) break
    needed <- next_needed
  }
  # Keep helpers before callers and include only the selected transitive closure.
  selected <- definitions[intersect(names(definitions), needed)]
  # Keep the editable header focused on fields this analysis actually reads.
  fields <- function(x) {
    if (!is.call(x)) return(if (is.character(x)) x else character())
    found <- if (identical(x[[1L]], as.name("$")) && is.symbol(x[[3L]])) as.character(x[[3L]]) else character()
    if (is.call(x[[1L]])) found <- c(found, fields(x[[1L]]))
    for (i in seq_along(x)[-1L]) {
      if (identical(x[[1L]], as.name("function")) && i == 2L) next
      if (!identical(x[[i]], quote(expr = ))) found <- c(found, fields(x[[i]]))
    }
    found
  }
  used <- unique(unlist(lapply(selected, fields), use.names = FALSE))
  supplied <- names(Filter(function(x) is.character(x) && length(x) == 1L && nzchar(x), spec$inputs))
  spec$inputs <- spec$inputs[intersect(names(spec$inputs), union(used, supplied))]
  spec$params <- spec$params[intersect(names(spec$params), used)]
  spec$style <- spec$style[intersect(names(spec$style), used)]
  for (section in c("input", "analysis", "selection", "pathways", "style"))
    config[[section]] <- config[[section]][intersect(names(config[[section]]), used)]
  helpers <- unlist(lapply(selected, function(x) c(deparse(x, width.cutoff = 95L), "")), use.names = FALSE)
  packages <- unique(unlist(regmatches(helpers, gregexpr("[A-Za-z][A-Za-z0-9.]*::", helpers))))
  # The workstation's RNA-seq entry accepts Count, not Salmon quantification;
  # tximport remains a guarded optional branch inside the shared import helper.
  packages <- setdiff(sub("::$", "", packages), c("base", "utils", "stats", "tools", "grDevices", "graphics", "grid", "tximport"))
  dump <- function(value) capture.output(dput(value))
  literal <- function(name, value) c(paste0(name, " <- ", dump(value)[1L]), dump(value)[-1L], "")
  lines <- c("#!/usr/bin/env Rscript", "# 独立分析脚本：不需要 biometa、Shiny 或后台服务。",
    if (portable) "# 将本文件与 data 文件夹一起分享；缺少的软件包请先安装。" else
      "# 输入地址指向本机任务快照；跨电脑分享请下载结果包中的脚本与 data 文件夹。",
    "# 1. 工作目录与 R 环境", paste0("# 导出时使用 R ", getRversion(), "；可在 RStudio 中选择对应 R 版本。"),
    if (portable) c("# 修改为本脚本所在目录，再运行全部代码。", "setwd(\".\")") else
      paste0("setwd(", encodeString(if (length(present)) dirname(present[[1L]]) else getwd(), quote = '"'), ")"),
    "", "# 2. 加载软件包", paste0("library(", sort(packages), ")"), "",
    "# 3. 输入文件（修改这些地址即可用于自己的数据）", literal("input_files", spec$inputs),
    "# 4. 分析参数（阈值、比较方向、聚类与注释设置）", literal("parameters", spec$params),
    literal("analysis_config", config),
    "# 5. 图像导出设置：尺寸单位英寸，分辨率单位 dpi", literal("plot_settings", spec$style),
    'output_directory <- "analysis_results"', "",
    "# 6. 当前分析需要的函数；实现已包含在本脚本内。", if (!is.null(legacy)) literal("legacy_code", legacy), helpers,
    "# 7. 导入、分析、绘图并导出结果", 'dir.create(file.path(output_directory, "inputs"), recursive = TRUE, showWarnings = FALSE)',
    'output_directory <- normalizePath(output_directory, winslash = "/", mustWork = TRUE)',
    'input_files <- lapply(input_files, function(path) if (nzchar(path)) normalizePath(path, winslash = "/", mustWork = TRUE) else "")',
    paste0('analysis_request <- list(tool = "', spec$tool, '", inputs = input_files, params = parameters, style = plot_settings',
      if (!is.null(spec$upstream_deg)) paste0(", upstream_deg = ", encodeString(spec$upstream_deg, quote = '"')), ")"),
    "tb_run_request(analysis_request, getwd(), output_directory)",
    "# 8. 记录环境并结束", 'writeLines(capture.output(sessionInfo()), file.path(output_directory, "sessionInfo.txt"))',
    'message("分析结束，结果保存至：", normalizePath(output_directory))')
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}
