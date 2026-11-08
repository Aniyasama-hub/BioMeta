# 公共接口：路径、版本、数据校验、哈希及可复现输出。
`%||%` <- function(x, y) if (is.null(x)) y else x

require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("缺少依赖：", paste(missing, collapse = ", "), call. = FALSE)
}

read_table <- function(path) {
  separator <- if (tolower(tools::file_ext(path)) %in% c("tsv", "txt")) "\t" else ","
  utils::read.table(path, header = TRUE, sep = separator, check.names = FALSE,
                    stringsAsFactors = FALSE, colClasses = "character", quote = "\"",
                    comment.char = "", fileEncoding = "UTF-8-BOM")
}

write_table <- function(data, path) {
  utils::write.csv(data, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
}

absolute_path <- function(path, base) {
  if (is.null(path)) return(NULL)
  if (!grepl("^([A-Za-z]:[/\\\\]|/)", path)) path <- file.path(base, path)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

load_config <- function(path) {
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)
  cfg <- env$config
  base <- dirname(normalizePath(path, winslash = "/", mustWork = TRUE))
  for (name in c("samples", "counts", "genes", "salmon_dir", "tx2gene", "reference_manifest")) {
    cfg$input[[name]] <- absolute_path(cfg$input[[name]], base)
  }
  cfg$project$output <- absolute_path(cfg$project$output, base)
  cfg$selection$target_genes <- absolute_path(cfg$selection$target_genes, base)
  for (name in c("gmt", "ppi_edges")) {
    cfg$pathways[[name]] <- absolute_path(cfg$pathways[[name]], base)
  }
  if (length(cfg$project$species) != 1L || is.na(cfg$project$species) || !nzchar(cfg$project$species)) stop("请声明物种。")
  if (!cfg$input$mode %in% c("counts", "salmon")) stop("input$mode须为counts或salmon。")
  if (!cfg$selection$direction %in% c("all", "up", "down")) stop("direction须为all/up/down。")
  if (cfg$selection$padj_cutoff <= 0 || cfg$selection$padj_cutoff > 1 ||
      cfg$selection$log2fc_cutoff < 0) stop("FDR须在(0,1]，log2FC幅度下限须非负。")
  if (cfg$analysis$alpha <= 0 || cfg$analysis$alpha > 1 ||
      cfg$analysis$min_count < 0 || cfg$analysis$min_samples < 1) {
    stop("alpha须在(0,1]、min_count非负、min_samples至少为1。")
  }
  if (cfg$selection$heatmap_top_n < 1 || cfg$selection$pca_top_genes < 2 ||
      cfg$selection$pathway_top_n < 1 || cfg$selection$label_top_n < 0) {
    stop("Top N数量不合法。")
  }
  cfg
}

read_samples <- function(cfg) {
  samples <- read_table(cfg$input$samples)
  required <- c("sample_id", "condition", "batch", "include")
  if (!all(required %in% names(samples))) stop("样本表缺少：", paste(required, collapse = ", "))
  if (any(!toupper(samples$include) %in% c("TRUE", "FALSE"))) stop("include只能为TRUE/FALSE。")
  samples <- samples[toupper(samples$include) == "TRUE", , drop = FALSE]
  if (!"source_sample_id" %in% names(samples)) samples$source_sample_id <- samples$sample_id
  if (nrow(samples) < 3 || nrow(samples) > cfg$project$max_samples) {
    stop("纳入样本须在 3 到 ", cfg$project$max_samples, " 个之间，并有足够残差自由度。")
  }
  if (cfg$analysis$min_samples > nrow(samples)) stop("min_samples不能超过入组样本数。")
  if (anyDuplicated(samples$sample_id) ||
      any(!grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", samples$sample_id))) {
    stop("sample_id须唯一且仅含英文字母、数字、下划线、点、短横线。")
  }
  if (anyDuplicated(samples$source_sample_id) || any(!nzchar(samples$source_sample_id))) {
    stop("source_sample_id必须非空唯一，用于原始Count列映射。")
  }
  samples$condition <- factor(samples$condition, levels = cfg$analysis$condition_levels)
  samples$batch <- factor(samples$batch)
  if (anyNA(samples$condition) || anyNA(samples$batch)) stop("分组/批次缺失或不在配置levels中。")
  if (any(as.character(samples$batch) == "")) stop("批次不能为空；单批次可填batch1。")
  groups <- table(samples$condition)
  if (any(groups < 2)) stop("每个声明的分组至少需要两个生物学重复。")
  if (!all(unlist(cfg$contrast) %in% levels(samples$condition)) ||
      cfg$contrast$numerator == cfg$contrast$denominator) stop("比较组配置错误。")
  rownames(samples) <- samples$sample_id
  samples
}

make_design <- function(samples, cfg) {
  variables <- cfg$analysis$covariates
  if (cfg$analysis$use_batch) {
    if (nlevels(samples$batch) < 2) stop("启用批次建模需要至少两个批次。")
    variables <- c(variables, "batch")
  }
  variables <- c(setdiff(unique(variables), "condition"), "condition")
  if (!all(variables %in% names(samples))) stop("设计协变量在样本表中不存在。")
  for (name in cfg$analysis$covariates) {
    # CSV协变量默认按分类变量处理；连续协变量需在导入接口中明确转换。
    samples[[name]] <- factor(samples[[name]])
    if (anyNA(samples[[name]]) || any(as.character(samples[[name]]) == "")) {
      stop("协变量缺失：", name)
    }
  }
  formula <- stats::reformulate(variables)
  design <- stats::model.matrix(formula, samples)
  if (qr(design)$rank < ncol(design)) stop("设计矩阵不满秩：批次/分组或协变量混杂。")
  if (nrow(design) <= ncol(design)) stop("设计没有残差自由度。")
  list(formula = formula, matrix = design, samples = samples)
}

file_fingerprint <- function(paths) {
  paths <- unique(paths[!is.na(paths) & nzchar(paths)])
  if (!all(file.exists(paths))) stop("输入文件不存在：", paste(paths[!file.exists(paths)], collapse = ", "))
  hashes <- vapply(paths, digest::digest, character(1), algo = "sha256", file = TRUE)
  stats::setNames(as.list(hashes), paths)
}

package_versions <- function(packages) {
  stats::setNames(lapply(packages, function(p) {
    if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "missing"
  }), packages)
}

selection_mask <- function(deg, selection) {
  fc <- deg[[selection$lfc_column]]
  if (is.null(fc)) stop("不存在所选log2FC列：", selection$lfc_column)
  hit <- is.finite(deg$padj) & is.finite(fc) &
    deg$padj < selection$padj_cutoff & abs(fc) >= selection$log2fc_cutoff
  if (selection$direction == "up") hit <- hit & fc > 0
  if (selection$direction == "down") hit <- hit & fc < 0
  hit
}

write_manifest <- function(value, path) {
  jsonlite::write_json(value, path, pretty = TRUE, auto_unbox = TRUE,
                       null = "null", na = "null", digits = NA)
}

save_run_metadata <- function(cfg, directory, manifest) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  dput(cfg, file = file.path(directory, "config_resolved.txt"))
  write_manifest(manifest, file.path(directory, "manifest.json"))
  writeLines(capture.output(utils::sessionInfo()), file.path(directory, "sessionInfo.txt"))
}
