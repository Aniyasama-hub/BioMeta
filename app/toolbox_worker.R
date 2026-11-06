#!/usr/bin/env Rscript
# 独立进程负责计算；Shiny 主进程只收集参数和显示已落盘的结果。
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("用法：Rscript toolbox_worker.R <任务目录> <工作台目录>")
directory <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
root <- normalizePath(args[2], winslash = "/", mustWork = TRUE)
source(file.path(root, "R", "toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R", "toolbox_analysis.R"), encoding = "UTF-8")
source(file.path(root, "R", "group_comparisons.R"), encoding = "UTF-8")
source(file.path(root, "R", "network_import.R"), encoding = "UTF-8")
source(file.path(root, "R", "string_reference.R"), encoding = "UTF-8")
source(file.path(root, "R", "immune.R"), encoding = "UTF-8")
source(file.path(root, "R", "public_pathways.R"), encoding = "UTF-8")
source(file.path(root, "R", "toolbox_render.R"), encoding = "UTF-8")
source(file.path(root, "R", "general_plots.R"), encoding = "UTF-8")
source(file.path(root, "R", "general_plot_render.R"), encoding = "UTF-8")
source(file.path(root, "R", "figure_layout.R"), encoding = "UTF-8")
spec <- NULL
tryCatch({
  spec <- readRDS(file.path(directory, "request.rds"))
  if (is.null(spec$redraw_from)) tb_run_request(spec, root, directory) else tb_redraw_request(spec, root, directory)
}, error = function(error) {
  progress <- tb_read_status(directory)$progress
  code <- if (progress >= 85) "BW-O01" else "BW-A01"
  detail <- tb_error_text(error, spec, code)
  message(detail)
  tb_status_write(directory, "failed", error = detail,
                    summary = "任务未完成；详细错误见日志。")
  quit(status = 1L)
})
