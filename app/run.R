#!/usr/bin/env Rscript
# 入口只负责调度。analyze / pathways / prepare / plot 分开，避免改字体重算分析。
args <- commandArgs(trailingOnly = TRUE)
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", all_args[grepl("^--file=", all_args)][1])
root <- dirname(normalizePath(script, winslash = "/", mustWork = TRUE))
for (file in c("core.R", "analysis.R", "prepare.R", "pathways.R", "ppi_prepare.R", "style_schema.R", "plots.R")) {
  source(file.path(root, "R", file), encoding = "UTF-8")
}
if (length(args) %% 2 != 0) stop("参数须为 --名称 值；参见README。")
options <- list(config = file.path(root, "config", "project.R"), stage = "check",
                 type = "volcano", bundle = NULL)
for (i in if (length(args)) seq.int(1L, length(args), by = 2L) else integer()) {
  name <- sub("^--", "", args[i])
  if (!name %in% names(options)) stop("未知参数：", args[i])
  options[[name]] <- args[i + 1]
}
types <- strsplit(options$type, ",", fixed = TRUE)[[1]]
allowed_types <- c("pca", "volcano", "heatmap", "enrichment", "gsea", "gsva", "network")
if (!all(types %in% allowed_types)) stop("不支持的type；参见README。")
if (!options$stage %in% c("check", "analyze", "pathways", "prepare", "plot", "all")) {
  stop("stage支持check/analyze/pathways/prepare/plot/all。")
}
require_packages(c("digest", "jsonlite"))
cfg <- load_config(options$config)
code_hashes <- file_fingerprint(list.files(file.path(root, "R"), full.names = TRUE))

render_saved_bundle <- function(path, cfg) {
  bundle <- readRDS(path)
  require_packages(c("ggplot2", "svglite", "ggrepel"))
  if (bundle$type == "heatmap") require_packages(c("ComplexHeatmap", "circlize"))
  if (bundle$type == "gsea") require_packages("patchwork")
  key <- digest::digest(list(bundle = digest::digest(file = path, algo = "sha256"),
                              style = cfg$style, engine = code_hashes[[file.path(root, "R", "plots.R")]],
                              packages = package_versions(c("ggplot2", "ggrepel", "svglite",
                                                              "ComplexHeatmap", "circlize", "patchwork"))),
                         algo = "sha256")
  directory <- file.path(cfg$project$output, "figures", paste0(bundle$type, "_", substr(key, 1, 16)))
  export_bundle(bundle, directory)
  dput(cfg$style, file = file.path(directory, "style.R"))
  # 导出的绘图引擎是结果包的复现资产，不是原项目脚本备份。
  file.copy(file.path(root, "R", "plots.R"), file.path(directory, "plot_engine.R"), overwrite = TRUE)
  file.copy(file.path(root, "R", "style_schema.R"), directory, overwrite = TRUE)
  writeLines(c(
    "args <- commandArgs(trailingOnly = FALSE)",
    "path <- sub('^--file=', '', args[grepl('^--file=', args)][1])",
    "root <- dirname(normalizePath(path, winslash = '/', mustWork = TRUE))",
    "source(file.path(root, 'style_schema.R'), encoding = 'UTF-8')",
    "source(file.path(root, 'plot_engine.R'), encoding = 'UTF-8')",
    "render_bundle(readRDS(file.path(root, 'bundle.rds')),",
    "              dget(file.path(root, 'style.R')), root)"
  ), file.path(directory, "reproduce.R"))
  save_run_metadata(cfg, directory, list(status = "running", figure_key = key,
                                          source_bundle = normalizePath(path, winslash = "/")))
  files <- tryCatch(render_bundle(bundle, cfg$style, directory), error = function(error) {
    write_manifest(list(status = "failed", error = conditionMessage(error), figure_key = key),
                     file.path(directory, "manifest.json"))
    stop(error)
  })
  save_run_metadata(cfg, directory, list(status = "completed", figure_key = key,
                                          files = file_fingerprint(files), code = code_hashes,
                                          source_bundle = normalizePath(path, winslash = "/")))
  message("绘图结果包：", directory)
}

# 独立重画只需bundle+样式配置，不读取FASTQ、Count或差异模型。
if (options$stage == "plot") {
  if (is.null(options$bundle)) stop("plot阶段必须提供 --bundle 路径。")
  render_saved_bundle(options$bundle, cfg)
} else {
  samples <- read_samples(cfg)
  design <- make_design(samples, cfg)
  required <- c("DESeq2", "SummarizedExperiment")
  if (cfg$input$mode == "salmon") required <- c(required, "tximport")
  if (cfg$analysis$batch_visualization) required <- c(required, "limma")
  require_packages(required)
  input_paths <- c(cfg$input$samples, cfg$input$genes)
  if (cfg$input$mode == "counts") {
    input_paths <- c(input_paths, cfg$input$counts)
  } else {
    input_paths <- c(input_paths, cfg$input$tx2gene, cfg$input$reference_manifest,
                     file.path(cfg$input$salmon_dir, "run_manifest.json"),
                     file.path(cfg$input$salmon_dir, samples$sample_id, "sample.json"),
                     file.path(cfg$input$salmon_dir, samples$sample_id, "completed.json"),
                     file.path(cfg$input$salmon_dir, samples$sample_id, "salmon", "quant.sf"))
  }
  fingerprint <- list(
    schema_version = "1.0", project = cfg$project[c("id", "species", "max_samples")],
    input = cfg$input, files = file_fingerprint(input_paths), analysis = cfg$analysis,
    contrast = cfg$contrast, R_version = as.character(getRversion()),
    packages = package_versions(required),
    code = code_hashes[grepl("/(core|analysis)[.]R$", names(code_hashes))]
  )
  key <- digest::digest(fingerprint, algo = "sha256")
  directory <- file.path(cfg$project$output, "analyses", substr(key, 1, 16))
  analysis_path <- file.path(directory, "analysis.rds")
  if (options$stage == "check") {
    if (cfg$input$mode == "counts") {
      header <- names(utils::read.csv(cfg$input$counts, nrows = 0, check.names = FALSE,
                                      fileEncoding = "UTF-8-BOM"))
      if (!all(c(cfg$input$gene_id_col, samples$source_sample_id) %in% header)) {
        stop("Count表表头与gene_id/source_sample_id映射不一致。")
      }
    }
    message("配置、输入文件和基础依赖检查通过；尚未运行分析。")
    message("设计：", paste(deparse(design$formula), collapse = ""),
             "；纳入样本：", nrow(samples), "；分析目录：", directory)
  } else {
    if (options$stage %in% c("analyze", "all")) {
      if (file.exists(analysis_path)) {
        analysis <- readRDS(analysis_path)
        if (!identical(analysis$fingerprint, fingerprint)) stop("缓存指纹不一致。")
        message("复用分析：", directory)
      } else {
        save_run_metadata(cfg, directory, list(status = "running", analysis_key = key,
                                                fingerprint = fingerprint))
        analysis <- tryCatch(analyze_dataset(cfg, samples, directory, fingerprint),
                              error = function(error) {
          write_manifest(list(status = "failed", error = conditionMessage(error)),
                           file.path(directory, "manifest.json"))
          stop(error)
        })
        save_run_metadata(cfg, directory, list(status = "completed", analysis_key = key,
                                                fingerprint = fingerprint))
        message("基础分析完成：", directory)
      }
    } else {
      if (!file.exists(analysis_path)) stop("此配置对应的分析不存在，请先运行analyze阶段。")
      analysis <- readRDS(analysis_path)
      if (!identical(analysis$fingerprint, fingerprint)) stop("缓存指纹不一致。")
    }
    if (options$stage %in% c("pathways", "prepare", "all")) {
      pathways <- NULL
      if (options$stage == "pathways" && !length(cfg$pathways$enabled)) {
        stop("未启用通路模块；请先配置pathways$enabled与对应本地数据。")
      }
      needs_pathways <- options$stage == "pathways" ||
        any(types %in% c("enrichment", "gsea", "gsva", "network"))
      if (length(cfg$pathways$enabled) && needs_pathways) {
        pathway_key <- digest::digest(list(
          analysis_key = key, pathways = cfg$pathways,
          selection = cfg$selection[c("padj_cutoff", "log2fc_cutoff", "direction", "lfc_column")],
          files = file_fingerprint(c(cfg$pathways$gmt, cfg$pathways$ppi_edges)),
          packages = package_versions(c("clusterProfiler", "fgsea", "GSVA", "limma", "igraph", "BiocParallel")),
          code = code_hashes[grepl("/(core|pathways)[.]R$", names(code_hashes))]
        ), algo = "sha256")
        pathway_dir <- file.path(directory, "pathways", substr(pathway_key, 1, 16))
        pathway_path <- file.path(pathway_dir, "pathways.rds")
        if (options$stage %in% c("pathways", "all")) {
          if (file.exists(pathway_path)) pathways <- readRDS(pathway_path) else {
            save_run_metadata(cfg, pathway_dir, list(status = "running", pathway_key = pathway_key))
            pathways <- tryCatch(analyze_pathways(analysis, cfg, pathway_dir), error = function(error) {
              write_manifest(list(status = "failed", error = conditionMessage(error), pathway_key = pathway_key),
                               file.path(pathway_dir, "manifest.json"))
              stop(error)
            })
            saveRDS(pathways, pathway_path)
            save_run_metadata(cfg, pathway_dir, list(status = "completed", pathway_key = pathway_key))
          }
          message("通路分析：", pathway_dir)
        } else {
          if (!file.exists(pathway_path)) stop("通路参数已变化或结果不存在，请先运行pathways阶段。")
          pathways <- readRDS(pathway_path)
        }
      }
      if (options$stage %in% c("prepare", "all")) {
        selection_settings <- cfg$selection[c("padj_cutoff", "log2fc_cutoff", "direction", "lfc_column")]
        selection_key <- digest::digest(list(analysis_key = key, selection = selection_settings,
                                              code = code_hashes[grepl("/core[.]R$", names(code_hashes))]),
                                         algo = "sha256")
        selection_dir <- file.path(directory, "selections", substr(selection_key, 1, 16))
        dir.create(selection_dir, recursive = TRUE, showWarnings = FALSE)
        selected <- analysis$deg[selection_mask(analysis$deg, cfg$selection), , drop = FALSE]
        write_table(selected, file.path(selection_dir, "deg_selected.csv"))
        fc <- selected[[cfg$selection$lfc_column]]
        write_table(data.frame(
          numerator = cfg$contrast$numerator, denominator = cfg$contrast$denominator,
          model_genes = nrow(analysis$deg), selected = nrow(selected),
          up = sum(fc > 0), down = sum(fc < 0),
          padj_cutoff = cfg$selection$padj_cutoff, log2fc_cutoff = cfg$selection$log2fc_cutoff
        ), file.path(selection_dir, "deg_summary.csv"))
        save_run_metadata(cfg, selection_dir, list(status = "completed", selection_key = selection_key,
                                                    analysis_key = key, selection = selection_settings))
        message("DEG筛选结果：", selection_dir)
        for (type in types) {
          bundle <- prepare_bundle(analysis, cfg, type, pathways)
          bundle$provenance <- list(analysis_key = key, selection = cfg$selection,
                                     pathways = cfg$pathways, contrast = cfg$contrast,
                                     species = cfg$project$species, preparation_code = code_hashes)
          bundle_key <- digest::digest(bundle, algo = "sha256")
          bundle_dir <- file.path(directory, "prepared", paste0(type, "_", substr(bundle_key, 1, 16)))
          export_bundle(bundle, bundle_dir)
          save_run_metadata(cfg, bundle_dir, list(status = "completed", bundle_key = bundle_key,
                                                  analysis_key = key, type = type))
          message("绘图数据包：", file.path(bundle_dir, "bundle.rds"))
          if (options$stage == "all") render_saved_bundle(file.path(bundle_dir, "bundle.rds"), cfg)
        }
      }
    }
  }
}
