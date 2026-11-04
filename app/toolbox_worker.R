#!/usr/bin/env Rscript
# 独立进程负责计算；Shiny 主进程只收集参数和显示已落盘的结果。
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("用法：Rscript toolbox_worker.R <任务目录> <工作台目录>")
directory <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
root <- normalizePath(args[2], winslash = "/", mustWork = TRUE)
source(file.path(root, "R", "toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R", "toolbox_analysis.R"), encoding = "UTF-8")
source(file.path(root, "R", "network_import.R"), encoding = "UTF-8")
tryCatch({
  spec <- readRDS(file.path(directory, "request.rds"))
  tb_run_request(spec, root, directory)
}, error = function(error) {
  message(conditionMessage(error))
  tb_status_write(directory, "failed", error = conditionMessage(error),
                    summary = "任务未完成；详细错误见日志。")
  quit(status = 1L)
})
