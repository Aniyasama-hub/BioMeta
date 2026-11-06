#!/usr/bin/env Rscript
# 启动入口使用文件参数，避免 cmd / Windows PowerShell / R 三层引号解析。
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) stop("Expected app directory, port, browser flag and log file.")
root <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
log <- file(args[4], open = "wt", encoding = "UTF-8")
sink(log, split = TRUE)
sink(log, type = "message")
status <- tryCatch({
  cat("BioWorkbench startup:", format(Sys.time()), "\n")
  cat("Application:", root, "\nR:", R.version.string, "\n")
  settings_path <- file.path(root, "results", "toolbox", "settings.json")
  if (file.exists(settings_path) && requireNamespace("jsonlite", quietly = TRUE)) {
    settings <- jsonlite::read_json(settings_path, simplifyVector = TRUE)
    lib <- settings$package_library
    if (identical(settings$library_r, as.character(getRversion())) && length(lib) == 1L && dir.exists(lib)) {
      .libPaths(c(lib, .libPaths()))
      Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
    }
  }
  if (!requireNamespace("shiny", quietly = TRUE)) stop("Missing package shiny in this R installation.")
  Sys.setenv(BIOWORKBENCH_HOME = dirname(root))
  shiny::runApp(root, host = "127.0.0.1", port = as.integer(args[2]),
                 launch.browser = identical(args[3], "TRUE"))
  0L
}, error = function(error) {
  message("STARTUP ERROR: ", conditionMessage(error))
  1L
})
sink(type = "message")
sink()
close(log)
quit(status = status)
